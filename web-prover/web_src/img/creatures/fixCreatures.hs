import qualified Data.Map as Map
import Data.Char
import System.Environment
import System.Directory
import System.FilePath
import Data.List
import Text.Show.Pretty

main = listAll

getPings =
  do xs <- getDirectoryContents "."
     return (filter ((== ".png") . takeExtension) xs)

listAll =
  do xs <- getPings
     putStrLn $ ppShow $ map head $ group $ sort $ map getName xs

getName xs =
  case break (== '_') (reverse xs) of
    (as,_:bs) -> reverse bs
    (_,[])    -> error xs

renAll = mapM_ (\f -> renameFile f (ren f)) =<< getPings

ren = cvt1
  where
  cvt1 (x : xs) = toLower x : cvt2 xs
  cvt1 []       = []

  cvt2 (x : xs) | isUpper x = '_' : toLower x : cvt2 xs
  cvt2 (x : xs)             = x : cvt2 xs
  cvt2 []                   = []
