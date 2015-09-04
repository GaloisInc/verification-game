{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternGuards #-}
module JsonStorm where

import           Language.Why3.PP(ppT)
import           Language.Why3.AST(Type)

import           Data.Proxy(Proxy(Proxy))
import           Data.Aeson (ToJSON(..), (.=))
import qualified Data.Aeson as JS
import           Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.HashMap.Strict as HashMap
import           Data.Map ( Map )
import qualified Data.Map as Map
import           Data.Maybe ( catMaybes )
import           Text.PrettyPrint(Doc, text, ($$), brackets, (<+>), (<>), vcat)
import qualified Data.Vector as Vector
import           Control.Monad(guard)


data JsonMode = MakeJson    -- ^ Generate JSON as usual
              | MakeDocs    -- ^ Generate docs about the structure
  deriving (Read,Show,Eq)

-- JSON generation for storm
class JsonStorm a where

  -- | Used for documentation.  One element per sum-type constructor.
  -- The elements need to be only defined enough for `toJS MakeDocs` to work.
  docExamples :: [(Text, a)]

  -- | A name for these types of values.
  jsShortDocs :: proxy a -> JS.Value

  -- | Generate either full JSON or just docs, depending on the mode.
  toJS        :: JsonMode -> a -> JS.Value

{-
prettyDocs :: JsonStorm a => proxy a -> [Doc]
prettyDocs = map renderSchema . makeDocs
-}

type Example = (Text, JS.Value)

-- | Docuementation for the various cases fo some type.
makeDocs :: JsonStorm a => proxy a -> [ Example ]
makeDocs ty = [ (txt,toJS MakeDocs x) | (txt,x) <- examples ty ]
  where
  examples :: JsonStorm b => proxy b -> [(Text, b)]
  examples _ = docExamples

-- | Render a value to JSON, as usual.
makeJson :: JsonStorm a => a -> JS.Value
makeJson a = toJS MakeJson a

-- | Use this when rendering JSON for a nested value.
-- This will ensure that docuementation is generated correctly.
nestJS :: JsonStorm a => JsonMode -> a -> JS.Value
nestJS MakeJson a = makeJson a
nestJS MakeDocs a = jsShortDocs (Just a)


noExampleDoc :: a -> (Text, a)
noExampleDoc a = ("", a)

unusedValue :: a
unusedValue = error "We should not look at this"

unusedValue' :: String -> a
unusedValue' x = error ("We should not look at this: " ++ x)




noDocs :: JsonStorm a => (a -> JS.Value) -> JsonMode -> a -> JS.Value
noDocs f mode thing =
  case mode of
    MakeDocs -> jsShortDocs (Just thing)
    MakeJson -> f thing


instance JsonStorm Int where
  docExamples    = [ noExampleDoc unusedValue ]
  jsShortDocs _  = jsType "integer"
  toJS           = noDocs toJSON

instance JsonStorm Integer where
  docExamples   = [ noExampleDoc unusedValue ]
  jsShortDocs _ = jsType "integer"
  toJS          = noDocs toJSON

instance JsonStorm Text where
  docExamples   = [ noExampleDoc unusedValue ]
  jsShortDocs _ = jsType "string"
  toJS          = noDocs toJSON

instance JsonStorm Bool where
  docExamples   = [ noExampleDoc unusedValue ]
  jsShortDocs _ = jsType "boolean"
  toJS          = noDocs toJSON



elemType :: proxy (f a) -> Proxy a
elemType _ = Proxy

instance JsonStorm a => JsonStorm [a] where
  docExamples       = [ noExampleDoc unusedValue ]
  jsShortDocs list  = jsList $ jsShortDocs $ elemType list
  toJS              = noDocs $ toJSON . fmap (toJS MakeJson)

instance JsonStorm a => JsonStorm (Maybe a) where
  docExamples     = [ noExampleDoc unusedValue ]
  jsShortDocs mb  = jsOptional $ jsShortDocs $ elemType mb
  toJS            = noDocs $ toJSON . fmap (toJS MakeJson)

instance JsonStorm Type where

  toJS mode t     = JS.object [ "text" .= nestJS mode
                                                (Text.pack (show (ppT t))) ]

  jsShortDocs _   = jsType "Type"
  docExamples     = [ noExampleDoc unusedValue ]


--------------------------------------------------------------------------------
-- Specifying schemas

jsType :: Text -> JS.Value
jsType ty = JS.object [ "__type__" .= ty ]

jsList :: JS.Value -> JS.Value
jsList ty = JS.object [ "__type__" .= ("[]" :: Text), "__elem__" .= ty ]

jsOptional :: JS.Value -> JS.Value
jsOptional ty = JS.object [ "__type__" .= ("Maybe" :: Text), "__elem__" .= ty ]


jsDocEntry :: JsonStorm a => proxy a -> Maybe (Text, [Example])
jsDocEntry a = jsDocEntry' (jsShortDocs a) (makeDocs a)

jsDocEntry' :: JS.Value -> [ Example ] -> Maybe (Text, [Example])
jsDocEntry' key vals =
  do JS.Object obj <- return key
     JS.String ty  <- HashMap.lookup "__type__" obj
     guard (ty /= "Maybe" && ty /= "[]")
     return (ty, vals)

jsDocMap :: [ Maybe (Text, [Example]) ] -> Map Text [Example]
jsDocMap = Map.fromList . catMaybes


--------------------------------------------------------------------------------



renderSchema :: JS.Value -> Doc
renderSchema (JS.Object obj)
  | Just (JS.String ty) <- HashMap.lookup "__type__" obj =
    case (ty, HashMap.lookup "__elem__" obj) of
      ("[]",    Just el) -> text "[" <+> renderSchema el <+> text "]"
      ("Maybe", Just el) -> renderSchema el <> text "?"
      _ -> text (Text.unpack ty)

renderSchema v =
  case v of
    JS.Object obj ->
      case HashMap.toList obj of
        [] -> text "{}"
        a : as ->
         let maxL   = maximum (map (Text.length . fst) (a : as))
             ppK x  = text (Text.unpack x) <> text ":" <>
                      text (replicate (maxL - Text.length x) ' ')

             el (k,v1) = ppK k <+> renderSchema v1
         in text "{" <+> el a $$
                vcat [ text "," <+> el b | b <- as ] $$ text "}"

    JS.Array arr
      | len == 0 -> text "[]"
      | len == 1 -> brackets (renderSchema (arr Vector.! 0))
      | otherwise ->
        (text "[" <+> renderSchema (arr Vector.! 0))
        $$ vcat [ text "," <+> renderSchema (arr Vector.! n)
                              | n <- [ 1 .. len - 1]]
        $$ text "]"
        where len = Vector.length arr

    JS.String n   -> text (show n)
    JS.Number n   -> text (show n)
    JS.Bool b     -> text (show b)
    JS.Null       -> text "null"






