module Test.Main.IxQueue where

import Prelude
import IxQueue as IxQ
import Foreign.Object (Object)
import Foreign.Object as Object
import Data.Tuple (Tuple (..))
import Data.Maybe (Maybe (..))
import Data.Traversable (for, class Traversable, sequence_)
import Data.Array as Array
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty as ArrayNE
import Data.UUID (genUUID)
import Effect (Effect)
import Effect.Random (randomInt)
import Effect.Ref (Ref)
import Effect.Ref as Ref
import Effect.Timer (setTimeout)
import Effect.Console (log)
import Partial.Unsafe (unsafePartial)



putManyAfterOnSync :: forall a
                    . Eq a
                   => NonEmptyArray a
                   -> (Boolean -> Effect Unit)
                   -> Effect Unit
putManyAfterOnSync xs onComplete = do
  q <- IxQ.new
  k <- show <$> genUUID
  (obtained :: Ref (Array a)) <- Ref.new []
  IxQ.on q k \x -> do
    newXs <- Ref.modify (\ys -> ys `Array.snoc` x) obtained
    if Array.length newXs == ArrayNE.length xs
       then onComplete (newXs == ArrayNE.toArray xs)
       else pure unit
  IxQ.putMany q k xs


putManyBroadcastsAfterOnSync :: forall a
                              . Eq a
                             => NonEmptyArray a
                             -> (Boolean -> Effect Unit)
                             -> Effect Unit
putManyBroadcastsAfterOnSync xs onComplete = do
  q <- IxQ.new
  n <- randomInt 1 10
  let replicateM :: forall m. Monad m => Int -> (Int -> m Unit) -> m Unit
      replicateM n' x
        | n' == 1 = x n'
        | otherwise = do
          x n'
          replicateM (n' - 1) x
  (obtained :: Ref (Object (Array a))) <- do
    o <- Ref.new Object.empty
    replicateM n \_ -> do
      k <- show <$> genUUID
      void (Ref.modify (Object.insert k []) o)
    pure o
  obtainedObj <- Ref.read obtained
  let forObj :: forall a m. Applicative m => Object a -> (String -> a -> m Unit) -> m Unit
      forObj obj f = sequence_ (Object.toArrayWithKey f obj)
  forObj obtainedObj \k _ -> do
    IxQ.on q k $ \x -> do
      let go' zs = zs `Array.snoc` x
          go ys = Object.update (Just <<< go') k ys
      newXs <- Ref.modify go obtained
      if Object.all (\_ x -> Array.length x == ArrayNE.length xs) newXs
        then onComplete (Object.all (\_ z -> z == ArrayNE.toArray xs) newXs)
        else pure unit
  IxQ.broadcastMany q xs
