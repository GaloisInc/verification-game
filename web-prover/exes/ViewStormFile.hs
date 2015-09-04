{-# LANGUAGE RecordWildCards #-}
import ProveBasics(names)
import Predicates( LevelPreds, lpredParamGroups, InputHole(..)
                 , ParamFlav(..), ParamWhen(..), ParamGroup(..))
import TaskGroup(TaskGroupData)
import SolutionMap(Assignment,FunSolution)
import BossLevel(BossLevel)
import Serial(decode)
import Prove(NameT(..))
import CTypes(TypeDB, decodeType, ParamType(..), BaseType(..),CType(..))


import           Data.Data(Data)
import           Data.Data.Lens(template)
import           Control.Lens(over)
import           Data.Proxy(Proxy(Proxy))
import qualified Data.ByteString.Lazy as LBS
import           Data.List(genericReplicate)
import           Data.Maybe(fromMaybe)
import           Text.Read(readMaybe)
import           Control.Monad(msum)
import           Text.Show.Pretty
import           System.Environment(getArgs)
import           Language.Why3.PP(ppT)
import           Text.PrettyPrint
import qualified Data.Map as Map
import qualified Data.Text as Text
import qualified Data.Text.Lazy as LText
import qualified Data.Text.Lazy.Encoding as LText

main :: IO ()
main = mapM_ ppFile =<< getArgs

ppFile :: FilePath -> IO ()
ppFile file = ppBytes =<< LBS.readFile file

ppBytes :: LBS.ByteString -> IO ()
ppBytes bs =
  putStrLn $
  fromMaybe "Failed to parse bytes" $
  msum [ attempt (Proxy :: Proxy TaskGroupData)
       -- , attempt (Proxy :: Proxy LevelPreds) -- careful, has to be after tgd
       , mbHoles
       , attempt (Proxy :: Proxy Assignment)
       , attempt (Proxy :: Proxy FunSolution)
       , attempt (Proxy :: Proxy BossLevel)
       , mbTypes
       ]
  where
  attempt p = ppShowAt p `fmap` decode bs
  mbHoles   = (show . prettyLevelPreds) `fmap` decode bs
  mbTypes   = fmap (show . ppTypeDB . decodeType)
            $ readMaybe
            $ LText.unpack
            $ LText.decodeUtf8 bs

ppShowAt :: (Data a, Show a) => Proxy a -> a -> String
ppShowAt _ x = ppShow (trimNames x)


trimNames :: Data s => s -> s
trimNames = over template simpHole . over template simpNames
  where
  simpNames :: NameT -> NameT
  simpNames n = n { nameTParams = [] }

  simpHole :: InputHole -> InputHole
  simpHole n = n { ihParams = [] }


prettyLevelPreds :: LevelPreds -> Doc
prettyLevelPreds = vcat . map pp . Map.toList . lpredParamGroups
  where
  pp (NameT { .. }, gs) = text (Text.unpack nameTName)
                          $$ nest 2 (vcat (zipWith3 ppP names nameTParams gs))

  ppP x ty g = nm x <+> ppG g <+> ppT ty

  ppF x = text $ case x of
                   SpecialParam -> "special"
                   GlobalParam  -> "global "
                   NormalParam  -> "normal "
                   LocalParam   -> "local  "
                   ReturnParam  -> "return "

  ppW x = text $ case x of
                   AtStart  -> "start"
                   AtCurLoc -> "here "

  ppG g = ppF (pgType g) <+> ppW (pgWhen g)

  nm x = text $ case Text.unpack x of
                  [c]   -> c : "  "
                  [c,d] -> c : d : " "
                  x     -> x

ppTypeDB :: TypeDB -> Doc
ppTypeDB (gNum, btys, holes) = vcat $ (text "Globals:" <+> int gNum)
                                    : map pp (Map.toList holes)
  where
  txt       = text . Text.unpack

  pp (x,ps) = txt x $$ nest 2 (vcat (zipWith ppP [ 1 .. ] ps))
  ppP n x   = num n <> text "." <+> txt (paramName x) <+> ppT (paramType x)
              <+> parens (text "size" <+> text (show (paramSize x)))
  ppT x     = text (genericReplicate (ctPtrDepth x) '*') <> ppB (ctBaseType x)
  ppB x     = case Map.lookup x btys of
                Just bt -> txt (btName bt)
                Nothing -> text "?"

  num n = text $ case show (n :: Int) of
                   [a]   -> "  " ++ [a]
                   [a,b] -> " " ++ [a,b]
                   x     -> x


