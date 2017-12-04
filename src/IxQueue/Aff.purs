module IxQueue.Aff where

import IxQueue.Internal (IxQueue, onDefaultIxQueue, onceDefaultIxQueue, putIxQueue, newIxQueue)

import Prelude
import Data.Maybe (Maybe (..))
import Data.Either (Either (..))
import Data.UUID (GENUUID, genUUID)
import Control.Monad.Aff (Aff, makeAff, nonCanceler)
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Ref (REF)



newtype IOQueues eff input output = IOQueues
  { input :: IxQueue eff input
  , output :: IxQueue eff output
  }


newIOQueues :: forall eff input output
             . Eff (ref :: REF | eff) (IOQueues (ref :: REF | eff) input output)
newIOQueues = do
  input <- newIxQueue
  output <- newIxQueue
  pure (IOQueues {input,output})



callAsync :: forall eff input output
           . IOQueues (ref :: REF, uuid :: GENUUID | eff) input output
          -> input
          -> Aff (ref :: REF, uuid :: GENUUID | eff) output
callAsync (IOQueues {input,output}) x =
  makeAff \resolve -> do
    k <- show <$> genUUID
    onceDefaultIxQueue output \_ y ->
      resolve (Right y)
    putIxQueue input k x
    pure nonCanceler -- FIXME delete handlers on cancel?


registerSyncOnce :: forall eff input output
                  . IOQueues (ref :: REF | eff) input output
                 -> (input -> Eff (ref :: REF | eff) output)
                 -> Eff (ref :: REF | eff) Unit
registerSyncOnce (IOQueues {input,output}) f =
  onceDefaultIxQueue input \ms x ->
    case ms of
      Nothing -> pure unit
      Just k -> putIxQueue output k =<< f x


registerSync :: forall eff input output
              . IOQueues (ref :: REF | eff) input output
             -> (input -> Eff (ref :: REF | eff) output)
             -> Eff (ref :: REF | eff) Unit
registerSync (IOQueues {input,output}) f =
  onDefaultIxQueue input \ms x ->
    case ms of
      Nothing -> pure unit
      Just k -> putIxQueue output k =<< f x
