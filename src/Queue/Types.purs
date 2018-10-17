module Queue.Types where

import Prelude (Unit)
import Effect (Effect)


foreign import kind SCOPE

foreign import data READ :: SCOPE

foreign import data WRITE :: SCOPE

type Handler a = a -> Effect Unit


class QueueScope (q :: # SCOPE -> Type -> Type) where
  readOnly     :: forall rw a. q (read  :: READ  | rw) a -> q (read  :: READ)  a
  writeOnly    :: forall rw a. q (write :: WRITE | rw) a -> q (write :: WRITE) a
  allowWriting :: forall rw a. q (read  :: READ)  a -> q (read  :: READ  | rw) a
  allowReading :: forall rw a. q (write :: WRITE) a -> q (write :: WRITE | rw) a
