module Queue.Types where

import Prelude (Unit)
import Control.Monad.Eff (Eff, kind Effect)


foreign import kind SCOPE

foreign import data READ :: SCOPE

foreign import data WRITE :: SCOPE

type Handler eff a = a -> Eff eff Unit


class QueueScope (q :: # SCOPE -> # Effect -> Type -> Type) where
  readOnly     :: forall rw eff a. q (read  :: READ  | rw) eff a -> q (read  :: READ)  eff a
  writeOnly    :: forall rw eff a. q (write :: WRITE | rw) eff a -> q (write :: WRITE) eff a
  allowWriting :: forall rw eff a. q (read  :: READ)  eff a -> q (read  :: READ  | rw) eff a
  allowReading :: forall rw eff a. q (write :: WRITE) eff a -> q (write :: WRITE | rw) eff a
