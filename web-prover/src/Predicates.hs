{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE PatternGuards #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE TypeFamilies #-}
module Predicates where

import Dirs
import SiteState
import StorageBackend
import Prove
import Serial
import Language.Why3.AST
import JsonStorm
import Theory(tAddr,tInt,tMap,matchTMap)

import           Control.Monad (mplus)
import           Data.Set ( Set )
import qualified Data.Set as Set

import           Data.Map ( Map )
import qualified Data.Map as Map
import           Data.Text ( Text )
import qualified Data.Text as Text
import           Data.Maybe(listToMaybe, fromMaybe)
import           Data.List(find)
import           GHC.Generics (Generic)
import           Data.Data (Data,Typeable)
import           Data.Aeson ( toJSON )

predDocs :: Map Text [ Example ]
predDocs = jsDocMap
  [ jsDocEntry (Nothing :: Maybe ParamFlav)
  , jsDocEntry (Nothing :: Maybe ParamWhen)
  ]


--------------------------------------------------------------------------------


data LevelPreds = LevelPreds
  { lpredPre   :: NameT
  , lpredLoops :: [NameT]
  , lpredPost  :: NameT
  , lpredCalls :: Map FunName CallInfo
    -- ^ pre and post conditions of functions that were called,
    -- one per call-site.

  , lpredParamGroups :: Map NameT [ ParamGroup ]
    -- ^ Used to tell us what the vearous parameters are used for.

  } deriving (Show,Generic,Data,Typeable)

instance Serial LevelPreds

-- | All calls to a function from another function.
data CallInfo = CallInfo
  { lpredCallPre   :: NameT
  , lpredCallPost  :: NameT
  , lpredCallSites :: [ (NameT, NameT) ]
  } deriving (Read,Show,Generic,Data,Typeable)

instance Serial CallInfo

-- | The inputs to a predicate, with function pre-post conditions grouped.
predInputs :: LevelPreds -> [UInput]
predInputs ps =
     NormalUInput (mk (lpredPre ps))
  :  NormalUInput (mk (lpredPost ps))
  :  map NormalUInput (map mk (lpredLoops ps))
  ++ [ CallUInput f (mk pre) (mk post)
            | (f,ci)     <- Map.toList (lpredCalls ps)
            , (pre, post) <- lpredCallSites ci ]

  where
  mk = inputHole (lpredParamGroups ps)

-- | The names of the schematic predicates, and their types.
predNameTs :: LevelPreds -> [NameT]
predNameTs ps =
  lpredPre ps : lpredPost ps : lpredLoops ps ++
                  concatMap fromCall (Map.elems $ lpredCalls ps)
  where
  fromCall ci = lpredCallPre ci
              : lpredCallPost ci
              : [ a | (x,y) <- lpredCallSites ci, a <- [x,y] ]

-- | The names of the schematic predicates.
predNames :: LevelPreds -> Set Name
predNames = Set.fromList . map nameTName . predNameTs

predInput :: Name -> LevelPreds -> Maybe UInput
predInput x LevelPreds { .. } =
  ((NormalUInput . mk) <$> find matches (lpredPre : lpredPost : lpredLoops))
  `mplus`
  listToMaybe [ CallUInput f (mk i) (mk j)
              | (f,ci) <- Map.toList lpredCalls
              , (i,j)  <- lpredCallSites ci
              , matches i || matches j
              ]

  where
  matches y = nameTName y == x
  mk        = inputHole lpredParamGroups


-- | All holes that might appear in a function.
funLevelPreds :: Readable (Local s) => SiteState s -> FunName -> IO LevelPreds
funLevelPreds site fun =
  do let file = holesFile fun
     txt <- storageReadFile (siteLocalStorage site) file
     case decode txt of
       Just ps -> return ps
       Nothing -> fail ("Failed to parse: " ++ show file) 


class ExpandAddrParams t where
  expandAddrParams :: t -> t

instance ExpandAddrParams NameT where
  expandAddrParams n = n { nameTParams = expandAddrsInType =<< nameTParams n }

instance ExpandAddrParams a => ExpandAddrParams [a] where
  expandAddrParams = map expandAddrParams

instance (ExpandAddrParams a, ExpandAddrParams b) =>
          ExpandAddrParams (a,b) where
  expandAddrParams (x,y) = (expandAddrParams x, expandAddrParams y)

instance ExpandAddrParams LevelPreds where
  expandAddrParams LevelPreds { .. } =
    LevelPreds
      { lpredPre         = expandAddrParams lpredPre
      , lpredPost        = expandAddrParams lpredPost
      , lpredLoops       = expandAddrParams lpredLoops
      , lpredCalls       = fmap expandAddrParams lpredCalls
      , lpredParamGroups = lpredParamGroups'
      }
     where
     lpredParamGroups' =
       Map.fromList
         [ (nameT { nameTParams = types' } , pgs')
           | (nameT, pgs) <- Map.toList lpredParamGroups
           , let types = nameTParams nameT
           , let (types', pgs') = unzip (concat (zipWith expandType types pgs))
           ]

     expandType ty pg = [ (ty',pg) | ty' <- expandAddrsInType ty ]

instance ExpandAddrParams CallInfo where
  expandAddrParams CallInfo { .. } =
    CallInfo
      { lpredCallPre   = expandAddrParams lpredCallPre
      , lpredCallPost  = expandAddrParams lpredCallPost
      , lpredCallSites = expandAddrParams lpredCallSites
      }

expandAddrsInType :: Type -> [Type]
expandAddrsInType t
  | t == tAddr                            = [ tInt, tInt ]
  | Just (k,v) <- matchTMap t, v == tAddr = [ tMap k tInt, tMap k tInt ]
  | otherwise                             = [ t ]

--------------------------------------------------------------------------------

data PredClass = Inv
               | FunPre       Name
               | FunPost      Name
               | CallSitePre  Call Text   -- Fuction called, call-site name
               | CallSitePost Call Text   -- Function called, call-site name
               | Other
                  deriving (Eq,Ord,Show, Generic, Data, Typeable)

data Call     = DynamicCall Text Text   -- line, column
              | StaticCall Name         -- known function
                  deriving (Eq,Ord,Show, Generic, Data, Typeable)


classifyPre :: Name -> Text -> Name -> PredClass
classifyPre fun sep predName =
  fromMaybe Other $
  do nm1 <- Text.stripPrefix "p_galois" predName
     nm2 <- Text.stripPrefix sep nm1
     ty  <- case Text.splitOn sep nm2 of
              []  -> Nothing
              res -> return (last res)
     nm3 <- Text.stripSuffix ty nm2
     nm4 <- Text.stripSuffix sep nm3
     case ty of
       "P" -> return (FunPre  nm4)
       "Q" -> return (FunPost nm4)
       _ | "I" `Text.isPrefixOf` ty -> return Inv
         | "C" `Text.isPrefixOf` ty ->
            do nm5 <- Text.stripPrefix fun nm4
               nm6 <- Text.stripPrefix sep nm5
               t   <- Text.stripPrefix "C" ty
               let getCallTgt x = 
                      do x1 <- Text.stripPrefix "_galois_dynamic_" x
                         x2 <- Text.stripPrefix sep x1
                         case Text.splitOn sep x2 of
                           [l,c] -> return (DynamicCall l c)
                           _     -> Nothing
                      `mplus` return (StaticCall x)
               mplus (do cs <- Text.stripSuffix "P" t
                         tgt <- getCallTgt nm6
                         return (CallSitePre tgt cs)
                     )
                     (do cs <- Text.stripSuffix "Q" t
                         tgt <- getCallTgt nm6
                         return (CallSitePost tgt cs)
                     )
         | otherwise -> Nothing



--------------------------------------------------------------------------------

-- A `UIInput` is like a hole, except that pre-and post conditions
-- of external calls are grouped.
data UInput = NormalUInput InputHole
            | CallUInput FunName InputHole InputHole
              deriving (Show,Generic, Data, Typeable)

instance ExpandAddrParams UInput where
  expandAddrParams ui =
    case ui of
      NormalUInput ih    -> NormalUInput (expandAddrParams ih)
      CallUInput f h1 h2 -> CallUInput f (expandAddrParams h1)
                                         (expandAddrParams h2)


instance Serial UInput

instance Eq UInput where
  x == y = compare x y == EQ

instance Ord UInput where
  compare (NormalUInput x) (NormalUInput y) = compare (ihName x) (ihName y)
  compare (NormalUInput _) _               = LT
  compare _ (NormalUInput _)               = GT
  compare (CallUInput _ x y) (CallUInput _ a b) =
    compare (ihName x, ihName y) (ihName a, ihName b)

uinputHoles :: UInput -> [InputHole]
uinputHoles ph =
  case ph of
    NormalUInput x -> [x]
    CallUInput _ x y -> [x,y]


-- | Information about a schematic predicate.
-- This is similiar to 'NameT' except we also keep track of what the
-- various parameter flavors, so we can show them differently in the UI.
data InputHole = InputHole
  { ihName    :: Name
  , ihParams  :: [(Type,ParamGroup)]
  } deriving (Show,Read,Generic, Data, Typeable)

instance ExpandAddrParams InputHole where
  expandAddrParams ih = ih { ihParams = concatMap expand (ihParams ih) }
    where
    expand (t,g) = [ (t',g) | t' <- expandAddrsInType t ]

instance Eq InputHole where
  x == y = ihName x == ihName y

instance Serial InputHole

-- | The `NameT` for an `InputHole`
ihNameT :: InputHole -> NameT
ihNameT InputHole { .. } = NameT { nameTName   = ihName
                                 , nameTParams = map fst ihParams
                                 }

ihTypes :: InputHole -> [Type]
ihTypes = map fst . ihParams


-- | Make an input hole, using the given information about the groups.
-- If we don't know what the groups are, then we use a default value.
inputHole :: Map NameT [ ParamGroup ] -> NameT -> InputHole
inputHole groups nm = InputHole
  { ihName   = nameTName nm
  , ihParams = zip (nameTParams nm) (Map.findWithDefault dflt nm groups)
  }
  where
  dflt = repeat ParamGroup { pgType = NormalParam, pgWhen = AtCurLoc }


--------------------------------------------------------------------------------
data ParamFlav  = SpecialParam | GlobalParam | NormalParam
                | LocalParam | ReturnParam
                  deriving (Eq,Ord,Read,Show,Generic,Data,Typeable)

data ParamWhen  = AtStart | AtCurLoc
                  deriving (Eq,Ord,Read,Show,Generic,Data,Typeable)

data ParamGroup = ParamGroup { pgType :: ParamFlav, pgWhen :: ParamWhen }
                  deriving (Read,Show,Generic,Data,Typeable)

instance Serial ParamFlav
instance Serial ParamWhen
instance Serial ParamGroup

instance JsonStorm ParamWhen where
  toJS _mode AtStart  = toJSON ("start" :: Text)
  toJS _mode AtCurLoc = toJSON ("here"  :: Text)

  jsShortDocs _       = jsType "Parameter Time"
  docExamples =
    [ ("Value at function entry",   AtStart)
    , ("Value at current location", AtCurLoc)
    ]

instance JsonStorm ParamFlav where
  toJS _mode SpecialParam = toJSON ("special" :: Text)
  toJS _mode GlobalParam  = toJSON ("global"  :: Text)
  toJS _mode NormalParam  = toJSON ("normal"  :: Text)
  toJS _mode LocalParam   = toJSON ("local"   :: Text)
  toJS _mode ReturnParam  = toJSON ("return"  :: Text)

  jsShortDocs _       = jsType "Parameter purpose"
  docExamples =
    [ ("Extra heap parameter",                SpecialParam)
    , ("Global varaible",                     GlobalParam)
    , ("Function parameter",                  NormalParam)
    , ("Local varaible",                      LocalParam)
    , ("Return value",                        ReturnParam)
    ]




-- | Classify the various parameters in a predicate.
-- The resulting lists should have the same number of entries as there are parameters
-- in the predicate.
computeParamGroups :: Int -> LevelPreds -> Map NameT [ParamGroup]
computeParamGroups globNum LevelPreds { .. } =
  Map.fromList $ (lpredPre, preGroups)
               : (lpredPost, postGroups)
               : map loopGroups lpredLoops
              ++ concatMap callGroups (Map.elems lpredCalls)
  where
  prePost nmP nmQ =
    let grpP = preParamGroups (length (nameTParams nmP)) globNum
        funP = length [ () | ParamGroup { pgType = NormalParam } <- grpP ]
        grpQ = postParamGroups (length (nameTParams nmQ)) globNum funP
    in (grpP, grpQ, funP)

  (preGroups, postGroups, funPNum) = prePost lpredPre lpredPost
  loopGroups nmI = (nmI, loopParamGroups (length (nameTParams nmI)) globNum funPNum)
  callGroups CallInfo { .. } =
      let (grpP,grpQ,_) = prePost lpredCallPre lpredCallPost
      in (lpredCallPre, grpP)
       : (lpredCallPost, grpQ)
       : concat [ [ (p, map now grpP), (q, grpQ) ] | (p,q) <- lpredCallSites ]

  now p = p { pgWhen = AtCurLoc }



-- WARNING: The code below is closely linked to how decorator works!!

preParamGroups :: Int           {- ^ Total number of params -} ->
                  Int           {- ^ Number of globals -}      ->
                  [ParamGroup]  {- ^ Groups of params, same length as params -}
preParamGroups allNum globNum =
  [ ParamGroup { pgWhen = AtStart, pgType = t } |
      t <- replicate 4       SpecialParam ++
           replicate globNum GlobalParam  ++
           replicate normNum NormalParam
  ]
  where
  normNum       = allNum - 4 - globNum


postParamGroups :: Int           {- ^ Total number of params -} ->
                   Int           {- ^ Number of globals      -} ->
                   Int           {- ^ Number of fun params   -} ->
                   [ParamGroup]  {- ^ Groups of params, same length as params -}
postParamGroups allNum globNum funPNum =
  replicate 4       ParamGroup { pgWhen = AtCurLoc, pgType = SpecialParam } ++
  replicate 4       ParamGroup { pgWhen = AtStart,  pgType = SpecialParam } ++
  replicate retNum  ParamGroup { pgWhen = AtCurLoc, pgType = ReturnParam } ++
  replicate globNum ParamGroup { pgWhen = AtStart,  pgType = GlobalParam } ++
  replicate funPNum ParamGroup { pgWhen = AtStart,  pgType = NormalParam } ++
  replicate globNum ParamGroup { pgWhen = AtCurLoc, pgType = GlobalParam }
  where
  retNum = allNum - 2 * (4 + globNum) - funPNum


loopParamGroups :: Int            {- ^ Total number of params       -} ->
                   Int            {- ^ Number of globals            -} ->
                   Int            {- ^ Number of function arguments -} ->
                   [ParamGroup]
loopParamGroups allNum globNum funPNum =
  replicate 4       ParamGroup { pgWhen = AtCurLoc, pgType = SpecialParam } ++
  replicate 4       ParamGroup { pgWhen = AtStart,  pgType = SpecialParam } ++
  replicate globNum ParamGroup { pgWhen = AtStart,  pgType = GlobalParam  } ++
  replicate funPNum ParamGroup { pgWhen = AtStart,  pgType = NormalParam  } ++
  replicate globNum ParamGroup { pgWhen = AtCurLoc, pgType = GlobalParam  } ++
  replicate locNum  ParamGroup { pgWhen = AtCurLoc, pgType = LocalParam   } ++
  replicate funPNum ParamGroup { pgWhen = AtCurLoc, pgType = NormalParam  }
  where
  locNum = allNum - 2 * (4 + globNum + funPNum)






