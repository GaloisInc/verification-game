{-# LANGUAGE TypeFamilies #-}

module Utils.AsList where

import           Control.Lens (Iso', iso)

import           Data.Set    (Set)
import           Data.IntSet (IntSet)
import           Data.Map    (Map)
import           Data.IntMap (IntMap)
import           Data.Vector (Vector)
import qualified Data.Set    as Set
import qualified Data.IntSet as IntSet
import qualified Data.Map    as Map
import qualified Data.IntMap as IntMap
import qualified Data.Vector as Vector

class AsList a where
  type ListElem a
  list :: Iso' [ListElem a] a

instance Ord a => AsList (Set a) where
  type ListElem (Set a) = a
  list = iso Set.fromList Set.toList

instance AsList IntSet where
  type ListElem IntSet = Int
  list = iso IntSet.fromList IntSet.toList

instance Ord k => AsList (Map k v) where
  type ListElem (Map k v) = (k,v)
  list = iso Map.fromList Map.toList

instance AsList (IntMap v) where
  type ListElem (IntMap v) = (Int,v)
  list = iso IntMap.fromList IntMap.toList

instance AsList (Vector a) where
  type ListElem (Vector a) = a
  list = iso Vector.fromList Vector.toList
