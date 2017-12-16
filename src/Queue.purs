module Queue
  ( module Queue.Internal
  , module Queue.Scope
  ) where

import Queue.Scope (kind SCOPE, READ, WRITE)
import Queue.Internal (Queue, newQueue, onQueue, putQueue, putManyQueue, takeQueue, readQueue, readOnly, writeOnly, allowReading, allowWriting)
