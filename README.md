# PureScript-Queue

The pub/sub model captures a simple concept - assign "handlers" to an event manager of
some kind, and delegate messages to those handlers by issuing events.

This library is an implementation of a trivial pub/sub model for PureScript:

```purescript
import Queue (Queue, READ, WRITE, newQueue, onQueue, putQueue)

type Effects eff = (console :: CONSOLE | eff)

main :: forall eff. Eff (Effects eff) Unit
main = do
  (q :: Queue (read :: READ, write :: WRITE) (Effects eff) Int) <- newQueue
  
  onQueue (readOnly q) \x -> logShow x
  
  putQueue (writeOnly q) 1
  putQueue q 2
```

> The calls to `readOnly` and `writeOnly` aren't necessary; they're just to demonstrate
> the ability to quarantine sections of your code which you only which to expose
> `(read :: READ)` or `(write :: WRITE)` as the facilities available to the queue.

It tries to immitate similar functionality to `Chan`s from Haskell, but isn't nearly as cool.
We get something similar to it; blocking when data is available, using the `Queue.Aff` module
and its siblings.

The `Queue` module provides a set-like perspective on handlers (you can additively register individual event
handlers, but can only clear them all at once), while the `IxQueue` module treats handlers
as an _indexed mapping_, allowing you to distinguish which
handler receives a message (opposed to broadcasting to all handlers), or descrepently remove a
single handler from the map (can be useful for dynamic allocation of multiple handlers to the same data).
There's also a `Queue.One` module, which has an implementation where there's
at most _one_ handler on the queue at any given time.

The behavior of this library is such that, if no handlers are registered, then
store pending messages first-in-first-out until one is available.

`Queue` is useful if you know the network of handlers is _static_ for the lifetime of their operation,
or at least strictly additive. `IxQueue` is useful when you need precice control over the presence of handlers
in a queue at runtime, each of which receive the same data. `Queue.One` is a convenient reduction of `Queue`,
where you only need to keep track of a single handler.

## Async

This library's main goal was to aid in cross-site interopability - almost localized
RPC mechanisms - through the `Queue.Aff`, `IxQueue.Aff`, and `Queue.One.Aff` modules, we can treat
message passing at a higher level as _procedure invocations_:

```purescript
import Queue.One.Aff (newIOQueues, registerSync, callAsync) -- most lightweight implementation
import Control.Monad.Aff (runAff_)

main = do
  io <- newIOQueues
  
  registerSync io $ \i -> do
    log $ "input: " <> show i
    let o = i + 1
    log $ "incremented: " <> show o
    pure o
    
  runAff_ logShow $ do
    result <- callAsync io 20
    liftEff $ log $ "Wow that was a super complicated delegated computation! Result: " <> show result
```

`Queue.Aff` is useful when you might have multiple `registerSyncOnce` calls waiting for the same input,
but clean themselves up, or multiple `registerSync` calls, if you know the network statically (deletion clears all of them).
`IxQueue.Aff` is useful when you need async calls, but need to integrate into an existing `IxQueue` of other recipients.
Note that in `IxQueue.Aff`, you need to pass the reference returned from `registerSync*` to `callAsync` - it's the
UUID key generated for the pending invocation. An advantage of `Queue.Aff` and `Queue.One.Aff`, naturally, is they don't need
to be registered before invoked - the input queue will hold on to the data.
