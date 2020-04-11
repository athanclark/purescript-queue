# PureScript-Queue

The pub/sub model captures a simple concept - assign "handlers" to an event manager of
some kind, and delegate messages to those handlers by issuing events. This is also considered
a "channel" in Haskell - something that stores messages until they are read.

The underlying implementations are pretty simple, because JavaScript is single-threaded. As a
result, we have the following architecture:

```purescript
import Queue (Queue, readOnly, writeOnly, READ, WRITE, new, on, put)


main :: Effect Unit
main = do
  (q :: Queue (read :: READ, write :: WRITE) Int) <- new
  
  -- assign a handler
  on (readOnly q) logShow
  
  -- put messages to the queue
  put (writeOnly q) 1
  put q 2 -- Doesn't need to be strictly write-only
```

> The calls to `readOnly` and `writeOnly` aren't necessary; they're just to demonstrate
> the ability to quarantine sections of your code, in which you only which to expose
> `(read :: READ)` or `(write :: WRITE)` access, as the only facilities available to the queue.

The _primary purpose_ of a queue is to decouple function invocation from parameter application -
if I don't have a function yet, but I have inputs for it, then I'll just write them to the queue. If
I have a function, but no inputs yet, then I'll just add the handler to the queue to await inputs.
_Furthermore_, if you want to _remove_ a handler, you should be able to.

It tries to imitate similar functionality to `Chan`s from Haskell, but isn't nearly as cool; the
`IO` monad in Haskell can block indefinitely while other threads write to the same channel, while our
`Queue`s can only do that in the `Aff` monad (single-threaded, but asynchronous). This functionality
is achieved using the `Queue.Aff` module and its siblings.

There are three flavors of `Queue`, sorted by their module:

- `module Queue.One` - the simplest version - in only allows for at-most _one_ handler - useful when you
  know there's only going to be one listener to the queue, but you don't know when the input will be
  available.
- `module Queue` - similar to `Queue.One`, except it allows for a _set_ of handlers at a time - you may
  _additively_ include individual handlers at any time, but because they can't be distinguished from each
  other as values (`Function` doesn't implement `Eq`), you can only delete _all of them at once_. This may
  be useful when you know in-advance that you won't be deleting any handlers.
- `module IxQueue` - similar to `Queue`, except it makes you _index_ your handlers by some `String`. This
  _names_ them, and allows you to delete individual handlers at any time without disrupting other ones.


## Verbiage

- `new` creates a new, empty queue.
- `put` inserts data into the queue. If there's at least one listener, it will supply that data to it.
  If not, it will be cached in-order (oldest to youngest).
- `draw` takes the oldest data from the queue, in `Aff`. 
- `on` assigns a handler that doesn't die by itself.
- `once` assigns a handler that dies after receiving _one_ input.

Some less important functions:

- `take` removes the oldest message, without invoking a handler.
- `pop` removes the youngest message, without invoking a handler.
- `drain` adds a handler that does nothing - just empties any residual data.
- `putMany` adds multiple values by traversing the handlers over the container.
- `takeMany` and `popMany` returns an array of values.
- `del` removes all handlers from the queue, but not affecting the cache if there is one.
- `read` observes the values in the queue, without affecting it's cache.
- `length` returns the length of the cache.


### Read and Write Scope

Initially, when using `new`, a queue is both read and write accessible, through the type-level flags `READ` and `WRITE`.
This may be undesirable for complex networks of queues, where one section of code clearly only supplies data, while another
one clearly only consumes it. There are functions for changing this:

- `readOnly` removes the `write :: WRITE` label from the row type
- `writeOnly` removes the `read :: READ` label from the row type
- `allowReading` adds the `read :: READ` label back to the row type
- `allowWriting` adds the `write :: WRITE` label back to the row type

This makes the type signature for a queue look something like `Queue (read :: READ, write :: WRITE) Foo`.


### Extra

There is also some extra kit defined in `module Queue.Types` - `debounceStatic`, `throttleStatic`, and `intersperseStatic`.
These functions take similar arguments - some _time_ value, and a _readable_ queue, and return a _writable_ queue, with some _thread_ (fiber).

Generally, in your code, you will be _listening_ to the queue you provide, while writing to the queue these functions return, to get
their intended effects.


- `debounceStatic` is intended to _drop_ messages sent before the time parameter - useful for user interface applications.
- `throttleStatic` is intended to _delay_ all messages sent before the time parameter, without loss. Useful for network applications.
- `intersperseStatic` is intended to _create_ messages if none are sent after the time parameter, without loss. Useful for
  connectivity in network applications (pings).


> Note: these variants are called "fooStatic" because there's only a single time value used, and wouldn't be capable of something
> more advanced like exponential falloff.


## Asynchronous message plumbing

This library's additional goal was to aid in asynchronous interop; having some source data originate asynchronously,
and the ability to handle it spontaneously. Through the `IOQueues` and `IxQueue.IOQueues` modules, we can treat
message passing to queues at a higher level, as _procedure invocations_. We do this by creating _two_ queues - one
for handling inputs to the handler(s), and one for returning results from the handler(s).

In the `module IOQueues` and `module IxQueue.IOQueues` modules, there's some somewhat confusing nomenclature:

- `new` creates an `IOQueues` - a pair of queues; one for input, one for output.
- `callAsync` puts an input in the `IOQueues`, and blocks until an output is available in `Aff`.
- `callAsyncEff` does the same thing as `callAsync`, but can't block in `Aff` and only operates in `Effect`.
- `registerSync` attaches a processing function to the `IOQueues`, taking an input and returning an output,
  but does so in lock-step - atomically adding a function to the system synchronously.
- `registerSyncOnce` does the same thing as `registerSync`, but removes itself after being invoked once.


```purescript
import Queue.One (Queue) as One
-- ^ most lightweight implementation, only one handler
import IOQueues (new, registerSync, callAsync, IOQueues)
import Effect.Aff (runAff_)

main = do
  (io :: IOQueues One.Queue Int Int) <- newIOQueues
  -- "IOQueues queue input output" means "using 'queue', take 'input' and make 'output'."
  
  let handler :: Int -> Effect Int
      handler i = do
        log $ "input: " <> show i
        let o = i + 1
        log $ "incremented: " <> show o
        pure o
  registerSync io handler -- attach the handler in Effect
    
  -- `resolveAff` does nothing - it's needed by `runAff_` - see `Effect.Aff` for details
  let resolveAff :: Either String Unit -> Effect Unit
      resolveAff _ = pure unit

  runAff_ resolveAff do
    result <- callAsync io 20 -- invoke delegated computation in Aff
    liftEffect $ log $ "Should be 21 - Result: " <> show result
```

### Multiple Handlers

`module IxQueue.IOQueues` is useful when you need async `IOQueues` calls, but need to integrate into an
existing `IxQueue` with a network of handlers and data supplied. The primary difference with this is that
through `IxQueue.IOQueues`, you need to pass a `String` reference to identify which handlers will be targeted
by what data.


Using a `module Queue` as an underlying `IOQueues` queue might be pretty confusing - it allows for multiple
`registerSync` handlers waiting for the same input, which would cause a race condition for the `callAsync`
invocation. However, if you mess with the internal output queue in the `IOQueues` and add extra handlers,
you may broadcast the results of the `registerSync` handler to multiple areas, without race conditions
(`callAsync` only reads from the output queue once). Either way, this use case would probably not be stable
or in your favor, and should generally be avoided.


# Contributing

This library has grown quite a lot over the years, and I still find it very useful.
[purescript-react-queue](https://pursuit.purescript.org/packages/purescript-react-queue) was spawned from this,
and I still use it all the time for managing react components.

If you have any ideas you'd like to see in this library, please file an issue or drop me a line. Thanks for using
it!
