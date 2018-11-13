module Test.Main where

import Test.Main.Queue.One as OneTest
import Test.QuickCheck (arbitrary)
import Test.QuickCheck.Gen as QC

import Prelude
import Data.Enum (succ)
import Data.Maybe (Maybe (Just))
import Data.Traversable (traverse_)
import Data.Array.NonEmpty (NonEmptyArray)
import Effect (Effect)
import Effect.Console (log, warn)
import Effect.Ref as Ref
import Partial.Unsafe (unsafePartial)


test :: (forall a. Eq a => NonEmptyArray a -> (Boolean -> Effect Unit) -> Effect Unit)
     -> Effect Unit
test go = do
  testCases <- QC.randomSample' 100 (arbitrary :: QC.Gen (NonEmptyArray Int))
  successes <- Ref.new 0
  let report :: Boolean -> Effect Unit
      report success
        | success = do
          let inc :: Int -> Int
              inc x = unsafePartial $ case succ x of
                Just y -> y
          new <- Ref.modify inc successes
          if new == 100 then log "success!" else pure unit
        | otherwise = warn "failure!"
  traverse_ (\testCase -> go testCase report) testCases

main :: Effect Unit
main = do
  log "Queue.One.putMany after Queue.One.on"
  test OneTest.putManyAfterOnSync
  log "Queue.One.putMany before Queue.One.on"
  test OneTest.putManyBeforeOnSync
  log "Queue.One.putMany after Queue.One.once at least once"
  test OneTest.putManyAfterOnceAtLeastOnce
  log "Queue.One.putMany after Queue.One.once only once"
  test OneTest.putManyAfterOnceOnlyOnce
