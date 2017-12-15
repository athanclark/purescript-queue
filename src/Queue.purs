module Queue
  ( module Queue.Internal
  ) where

import Queue.Internal (Queue, READ, WRITE, kind SCOPE, newQueue, onQueue, putQueue, putManyQueue, takeQueue, readQueue, readOnly, writeOnly, allowReading, allowWriting)
