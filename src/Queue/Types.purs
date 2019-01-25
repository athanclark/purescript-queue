module Queue.Types where

import Prelude (Unit)
import Data.Time.Duration (Milliseconds)
import Effect (Effect)
import Effect.Aff (Aff, Fiber)


foreign import kind SCOPE

foreign import data READ :: SCOPE

foreign import data WRITE :: SCOPE

type Handler a = a -> Effect Unit


class QueueScope (q :: # SCOPE -> Type -> Type) where
  readOnly     :: forall rw a. q (read  :: READ  | rw) a -> q (read  :: READ)  a
  writeOnly    :: forall rw a. q (write :: WRITE | rw) a -> q (write :: WRITE) a
  allowWriting :: forall rw a. q (read  :: READ)  a -> q (read  :: READ  | rw) a
  allowReading :: forall rw a. q (write :: WRITE) a -> q (write :: WRITE | rw) a


class QueueExtra (queue :: # SCOPE -> Type -> Type) where
  debounceStatic :: forall a. Milliseconds -> queue (read :: READ) a -> Aff {input :: queue (write :: WRITE) a, writer :: Fiber Unit}
  throttleStatic :: forall a. Milliseconds -> queue (read :: READ) a -> Aff {input :: queue (write :: WRITE) a, writer :: Fiber Unit}
  intersperseStatic :: forall a. Milliseconds -> Aff a -> queue (read :: READ) a -> Aff {input :: queue (write :: WRITE) a, writer :: Fiber Unit, listener :: Fiber Unit}
