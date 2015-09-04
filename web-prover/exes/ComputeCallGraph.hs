{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeFamilies #-}
module Main(main) where

import Dirs(FunName, funHash, listAllFuns)
import Predicates(funLevelPreds, lpredCalls)
import StorageBackend(localStorage, Readable, noStorage, disableWrite)
import SiteState

import qualified Data.Map as Map
import           Data.List(mapAccumL)
import           Text.PrettyPrint
import           Control.Exception

main :: IO ()
main =
  do siteState <- newSiteState (disableWrite localStorage) noStorage
     cg <- callGraph siteState
     print (export cg)

-- | Information about a single function.
data Node = Node { fun      :: FunName
                 , stage    :: Int
                 , calls    :: [FunName]
                 , calledBy :: [FunName]
                 } deriving Show

-- | JSON representation of a call-graph.
export :: [Node] -> Doc
export = block one "{" "}"
  where
  one pre Node { .. } =
    hang (pre <+> exportFun fun <> colon) 2 $ vcat
      [ text "{ \"stage\": "   <+> int stage
      , text ", \"calls\":"    <+> block oneFun "[" "]" calls
      , text ", \"calledBy\":" <+> block oneFun "[" "]" calledBy
      , text "}"
      ]

  oneFun pre f           = pre <+> exportFun f

  exportFun              = text . show . funHash

  block _   start end [] = text (start ++ end)
  block how start end xs = vcat (zipWith how (map text (start : repeat ",")) xs)
                           $$ text end

-- | Construct the call-graph for all functions that we know.
callGraph :: Readable (Local s) => SiteState s -> IO [Node]
callGraph siteState =
  do fs <- listAllFuns siteState
     cs <- mapM (getCalls siteState) fs
     let missing = [ f | c <- cs, f <- c, not (f `elem` fs) ]
         xs     = zip missing (repeat []) ++ zip fs cs
         invMap = Map.fromListWith (++) [ (g,[f]) | (f,gs) <- xs, g <- gs ]
         getCalledBy f = Map.findWithDefault [] f invMap
         stage  = 0 -- Temporary
     return $ setStages
              [ Node { calledBy = getCalledBy fun , ..  } | (fun,calls) <- xs ]



-- | Assumes no loops in the graph (i.e., no recursive functions).
setStages :: [Node] -> [Node]
setStages nodes0 = snd (mapAccumL go Map.empty nodes0)
  where
  nodeMap = Map.fromList [ (fun n, n) | n <- nodes0 ]

  go done nd =
    case Map.lookup (fun nd) done of
      Just s  -> (done, s)
      Nothing -> let (done1, nodes) = mapAccumL go' done (calls nd)
                     newStage       = maximum (0 : map ((+ 1) . stage) nodes)
                     node           = nd { stage = newStage }
                 in (Map.insert (fun nd) node done1, node)

  go' done nodeId      = case Map.lookup nodeId nodeMap of
                           Just node -> go done node
                           Nothing ->
                             error ("getStages: Missing node " ++ show nodeId)



-- | What functions are called by this function.
-- This does not use the `depends` infracstrucutre, it is extracted
-- directly from the `holes.hs` file.
getCalls :: Readable (Local s) => SiteState s -> FunName -> IO [FunName]
getCalls siteState fun =
  do ps <- funLevelPreds siteState fun
     return (Map.keys (lpredCalls ps))
  `catch` \SomeException {} -> return []




