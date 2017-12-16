module IxQueue
  ( module IxQueue.Internal
  , module Queue.Scope
  ) where

import IxQueue.Internal
  ( IxQueue (..)
  , readOnly, writeOnly, allowReading, allowWriting
  , newIxQueue, putIxQueue, putManyIxQueue, putOnlyIxQueue, putOnlyManyIxQueue
  , broadcastIxQueue, broadcastManyIxQueue
  , onDefaultIxQueue, onIxQueue, onceDefaultIxQueue, onceIxQueue
  , readDefaultIxQueue, readIxQueue, takeDefaultIxQueue, takeIxQueue
  , delDefaultIxQueue, delIxQueue, clearIxQueue
  )
import Queue.Scope (kind SCOPE, READ, WRITE)
