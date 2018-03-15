{-# LANGUAGE MultiParamTypeClasses, TypeFamilies, UndecidableInstances #-}
module Control.Abstract.Addressable where

import Control.Abstract.Analysis
import Control.Applicative
import Control.Monad ((<=<))
import Data.Abstract.Address
import Data.Abstract.Environment
import Data.Abstract.FreeVariables
import Data.Abstract.Heap
import Data.Abstract.Value
import Data.Monoid (Alt(..))
import Data.Semigroup.Reducer
import Prelude hiding (fail)

-- | Defines 'alloc'ation and 'deref'erencing of 'Address'es in a Heap.
class (Monad m, Ord l, l ~ LocationFor value, Reducer value (Cell l value)) => MonadAddressable l value m where
  deref :: Address l value -> m value

  alloc :: Name -> m (Address l value)

-- | Look up or allocate an address for a 'Name'.
lookupOrAlloc :: ( MonadAddressable (LocationFor value) value m
                 , MonadEnvironment value m
                 )
                 => Name
                 -> m (Address (LocationFor value) value)
lookupOrAlloc name = lookupLocalEnv name >>= maybe (alloc name) pure


letrec :: ( MonadAddressable (LocationFor value) value m
          , MonadEnvironment value m
          , MonadHeap value m
          )
       => Name
       -> m value
       -> m (value, Address (LocationFor value) value)
letrec name body = do
  addr <- lookupOrAlloc name
  v <- localEnv (envInsert name addr) body
  assign addr v
  pure (v, addr)


-- Instances

-- | 'Precise' locations are always 'alloc'ated a fresh 'Address', and 'deref'erence to the 'Latest' value written.
instance (MonadFail m, LocationFor value ~ Precise, MonadHeap value m) => MonadAddressable Precise value m where
  deref = derefWith (pure . unLatest)
  alloc _ = fmap (Address . Precise . heapSize) getHeap


-- | 'Monovariant' locations 'alloc'ate one 'Address' per unique variable name, and 'deref'erence once per stored value, nondeterministically.
instance (Alternative m, LocationFor value ~ Monovariant, MonadFail m, MonadHeap value m, Ord value) => MonadAddressable Monovariant value m where
  deref = derefWith (foldMapA pure)
  alloc = pure . Address . Monovariant

-- | Dereference the given 'Address' in the heap, using the supplied function to act on the cell, or failing if the address is uninitialized.
derefWith :: (MonadFail m, MonadHeap value m, Ord (LocationFor value)) => (CellFor value -> m a) -> Address (LocationFor value) value -> m a
derefWith with = maybe uninitializedAddress with <=< lookupHeap

-- | Fold a collection by mapping each element onto an 'Alternative' action.
foldMapA :: (Alternative m, Foldable t) => (b -> m a) -> t b -> m a
foldMapA f = getAlt . foldMap (Alt . f)

-- | Fail with a message denoting an uninitialized address (i.e. one which was 'alloc'ated, but never 'assign'ed a value before being 'deref'erenced).
uninitializedAddress :: MonadFail m => m a
uninitializedAddress = fail "uninitialized address"
