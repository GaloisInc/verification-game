{-# LANGUAGE PatternGuards  #-}
{-# LANGUAGE OverloadedStrings #-}

-- | This module contains functions which ideally would be in e.g. base

module Utils (findM
             , isSubExpr
             , checkMatch
             , substExpr
             , preview'
             , parallelTraverse
             , invokeProcess
             , getDirs
             , getFiles
             , option
             ) where

import           Control.Concurrent( forkIO, newChan, readChan, writeChan
                                    , newEmptyMVar, takeMVar, putMVar )
import           Control.Lens(Getting, preview, foldMapBy)
import           Control.Applicative(Alternative, (<|>), empty)
import           Control.Monad(filterM)
import qualified Control.Exception as X

import           Data.Foldable (foldlM, for_)
import           Data.List (find)
import           Data.Set ( Set )
import           Data.Traversable(for)
import qualified Data.Map as Map
import qualified Data.Set as Set
import           Data.Monoid(First)

import           Language.Why3.AST
import           Language.Why3.Names (freeNames)
import           Language.Why3.PP (ppE)
import           System.IO (hGetContents, hPutStr, hClose)
import           System.Process (waitForProcess, terminateProcess
                                , runInteractiveProcess)
import           System.Directory(doesDirectoryExist, getDirectoryContents)
import           System.FilePath((</>))


-- | Return (non-hidden) sub-directories of given directory.
-- The result is only the sub-directory name, not the entire path.
getDirs :: FilePath -> IO [FilePath]
getDirs dir =
  do fs <- getDirectoryContents dir
            `X.catch` \X.SomeException {} -> return []
     let isDir f = do yes <- doesDirectoryExist (dir </> f)
                      return (yes && take 1 f /= ".")
     filterM isDir fs

-- Get a list of the files in a directory excluding directories
-- and the dummy files which exist for git's benefit.
getFiles :: FilePath -> IO [FilePath]
getFiles dir =
  do fs <- getDirectoryContents dir
            `X.catch` \X.SomeException {} -> return []
     let isFile f | f == ".dummy" = return False
                  | otherwise     = do isDir <- doesDirectoryExist (dir </> f)
                                       return (not isDir)
     filterM isFile fs


parallelTraverse :: Traversable t =>
                    Int -> (Int -> a -> IO b) -> t a -> IO (t b)
parallelTraverse limit f ts =
  do controller <- newChan
     for_ [ 1 .. limit ] (writeChan controller)
     answers <- for ts $ \t -> do uid  <- readChan controller
                                  ans <- newEmptyMVar
                                  _   <- forkIO $ do a <- f uid t
                                                     putMVar ans a
                                                     writeChan controller uid
                                  return ans
     for answers takeMVar


-- Preview
preview' :: Alternative f => Getting (First a) t a -> t -> f a
preview' l x = maybe empty pure (preview l x)


-- | As for find with a monadic predicate.  This could be more
-- efficient (using continuations, say)
findM :: (Foldable t, Monad m) => (a -> m Bool) -> t a -> m (Maybe a)
findM p = foldlM liftedP Nothing 
  where
    liftedP Nothing v = do b <- p v
                           return $ if b then Just v else Nothing
    liftedP res _     = return res

isSubExpr :: Expr -> Expr -> Bool
isSubExpr lhs rhs = check rhs
  where
  check e
    | lhs == e   = True 
    | otherwise = go e
  -- e1 /= e
  go e =  case e of
            Lit _               -> False
            App _ es            -> any check es
            Let _ e1 e2         -> check e1 || check e2
            If e1 e2 e3         -> check e1 || check e2 || check e3
            Conn _ e1 e2        -> check e1 || check e2
            Not e'              -> check e'
            Field _ e'          -> check e'
            Record fs           -> any (check . snd) fs 
            Quant _ _ trs e'    -> any (any check) trs || check e'
            Labeled _ e'        -> check e'
            Cast e' _           -> check e'
            Match es alts       -> any check es || any (check . snd) alts

-- Basically, what is wrong with this set of substitutions?
checkMatch :: Set Name -> [(Expr, Expr)] -> [String]
checkMatch _ [] = []
checkMatch fvs ((e, _) : es) = problems ++ checkMatch fvs es
  where
    problems = overlaps ++ constants
    overlaps  = case find (\e' -> isSubExpr e e' || isSubExpr e' e) (map fst es) of
                  Nothing -> []
                  Just _  -> [ "Term " ++ show (ppE e) ++ " overlaps." ]
    constants = if Set.null (freeNames e `Set.intersection` fvs)
                   then []
                   else [ "Term " ++ show (ppE e) ++ " is constant." ]

-- | Performs simulteous substitution.  This is useful for performing matchin
--
-- This produces a best-effort result: in the case of constants and
-- repeated terms, there can be multiple results, leading to an
-- exponential number of possible matches.  For example, 
-- @
--    substExpr [("x", "y"), ("x", "z")] "x"
-- @
-- 
-- can yield one of ["x", "y", "z"]
--
-- c.f. checkMatch for a function which checks that there won't be problems.
-- 
-- WARNING: This assumes that no capturing of variables will occur, on
-- either side of the substitution.  c.f. apSubst for the case where
-- binders are taken into account (at least for the LHS of the equality)
--
-- FIXME: is this restriction reasonable?
    
substExpr :: [(Expr, Expr)] -> Expr -> Expr
substExpr substs srcExpr = check srcExpr
  where
  substsM = Map.fromList substs
  check e
    | Just e' <- Map.lookup e substsM = e'
    | otherwise = go e
  go e =
    case e of
      Lit _               -> e
      App _ []            -> e
      App x es            -> App x (map check es)

      Match es alts -> Match (map check es) $ map inAlt alts
        where
        inAlt (p,e') = (p, check e')

      Let p e1 e2         -> Let p (check e1) (check e2)

      Quant q as trs e'   -> Quant q as (map (map check) trs) (check e')

      If e1 e2 e3         -> If (check e1) (check e2) (check e3)
      Conn c e1 e2        -> Conn c (check e1) (check e2)
      Not e'              -> Not (check e')
      Field l e'          -> Field l (check e')
      Record fs           -> Record [ (x, check e') | (x,e') <- fs ]

      Cast e' t           -> Cast (check e') t
      Labeled l e'        -> Labeled l (check e')


invokeProcess ::
  FilePath                    {- ^ Executable file path         -} ->
  [String]                    {- ^ Arguments                    -} ->
  String                      {- ^ Stdin                        -} ->
  (String -> String -> IO ()) {- ^ Stdout -> Stderr -> callback -} ->
  IO ()

invokeProcess path args input callback =
  X.bracketOnError

    -- First, fork the process
    (runInteractiveProcess path args Nothing{- working dir-} Nothing{-env-})

    {- If we get killed, clean up the process and we are done.
    Not sure if the `wait` is strictly necessery, but we do it
    to avoid potential zombied processed.  Since we know that our
    provers are reasonably well behaved, we expect this to not cause
    a significant delay. -}

    (\(_,_,_,ph) -> terminateProcess ph >> waitForProcess ph)

    -- Once the process is started, we continue here
    (\(hIn,hOut,hErr,ph) ->
        do out      <- hGetContents hOut
           err      <- hGetContents hErr

           _ <- forkIO (hPutStr hIn input >> hClose hIn)
           _ <- forkIO (length err `seq` return ())

           _exitCode <- length out `seq` waitForProcess ph
           callback out err)


option :: (Foldable t, Alternative f) => t a -> f a
option = foldMapBy (<|>) empty pure
