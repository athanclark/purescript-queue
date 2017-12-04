module IxQueue.Aff where

import IxQueue.Internal (IxQueue, onDefaultIxQueue, onceDefaultIxQueue, putIxQueue)

import Prelude
import Data.Maybe (Maybe (..))
import Data.Either (Either (..))
import Data.UUID (GENUUID, genUUID)
import Control.Monad.Aff (Aff, runAff_, makeAff, nonCanceler)
import Control.Monad.Aff.AVar (AVAR, makeEmptyVar, putVar, takeVar)
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Ref (REF)

import Control.Monad.Eff.Console (log)


callAsync :: forall eff input output
           . IxQueue (ref :: REF, uuid :: GENUUID, avar :: AVAR | eff) input
          -> IxQueue (ref :: REF, uuid :: GENUUID, avar :: AVAR | eff) output
          -> input
          -> Aff (ref :: REF, uuid :: GENUUID, avar :: AVAR | eff) output
callAsync i o x =
  makeAff \resolve -> do
    k <- show <$> genUUID
    onceDefaultIxQueue o \_ y ->
      resolve (Right y)
    putIxQueue i k x
    pure nonCanceler


registerSyncOnce :: forall eff input output
                  . IxQueue (ref :: REF | eff) input
                 -> IxQueue (ref :: REF | eff) output
                 -> (input -> Eff (ref :: REF | eff) output)
                 -> Eff (ref :: REF | eff) Unit
registerSyncOnce i o f =
  onceDefaultIxQueue i \ms x ->
    case ms of
      Nothing -> pure unit
      Just k -> putIxQueue o k =<< f x


registerSync :: forall eff input output
              . IxQueue (ref :: REF | eff) input
             -> IxQueue (ref :: REF | eff) output
             -> (input -> Eff (ref :: REF | eff) output)
             -> Eff (ref :: REF | eff) Unit
registerSync i o f =
  onDefaultIxQueue i \ms x ->
    case ms of
      Nothing -> pure unit
      Just k -> putIxQueue o k =<< f x
