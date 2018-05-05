module Queue.Types where

import Prelude (Unit)
import Control.Monad.Eff (Eff, kind Effect)


foreign import kind SCOPE

foreign import data READ :: SCOPE

foreign import data WRITE :: SCOPE

type Handler eff a = a -> Eff eff Unit


class QueueScope (q :: # SCOPE -> # Effect -> Type) where
  readOnly     :: forall rw eff. q (read  :: READ  | rw) eff -> q (read  :: READ)  eff
  writeOnly    :: forall rw eff. q (write :: WRITE | rw) eff -> q (write :: WRITE) eff
  allowWriting :: forall rw eff. q (read  :: READ)  eff -> q (read  :: READ  | rw) eff
  allowReading :: forall rw eff. q (write :: WRITE) eff -> q (write :: WRITE | rw) eff
