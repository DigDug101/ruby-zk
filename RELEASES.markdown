This file notes feature differences and bugfixes contained between releases. 

### v1.0.0 ###

* allow for both :sequence and :sequential arguments to create, because I always forget which one is the "right one"

* add zk.register(:all) to recevie node updates for all nodes (i.e. not filtered on path)

* create now allows you to pass a path and options, instead of requiring the blank string

    zk.create('/path', '', :sequential => true)

    # now also

    zk.create('/path', :sequential => true)

* fix for shutdown: close! called from threadpool will do the right thing

### v0.9.1 ###

The "Don't forget to update the RELEASES file before pushing a new release" release

* Fix a fairly bad bug in event de-duplication (diff: http://is.gd/a1iKNc)
	
	This is fairly edge-case-y but could bite someone. If you'd set a watch
	when doing a get that failed because the node didn't exist, any subsequent
	attempts to set a watch would fail silently, because the client thought that the
	watch had already been set.
	
	We now wrap the operation in the setup_watcher! method, which rolls back the
	record-keeping of what watches have already been set for what nodes if an
	exception is raised.
	
	This change has the side-effect that certain operations (get,stat,exists?,children)
	will block event delivery until completion, because they need to have a consistent
	idea about what events are pending, and which have been delivered. This also means
	that calling these methods represent a synchronization point between user threads
	(these operations can only occur serially, not simultaneously).


### v0.9.0 ###

* Default threadpool size has been changed from 5 to 1. This should only affect people who are using the Election code.
* `ZK::Client::Base#register` delegates to its `event_handler` for convenience (so you can write `zk.register` instead of `zk.event_handler.register`, which always irked me)
* `ZK::Client::Base#event_dispatch_thread?` added to more easily allow users to tell if they're currently in the event thread (and possibly make decisions about the safety of their actions). This is now used by `block_until_node_deleted` in the Unixisms module, and prevents a situation where the user could deadlock event delivery.
* Fixed issue 9, where using a Locker in the main thread would never awaken if the connection was dropped or interrupted. Now a `ZK::Exceptions::InterruptedSession` exception (or mixee) will be thrown to alert the caller that something bad happened.
* `ZK::Find.find` now returns the results in sorted order.
* Added documentation explaining the Pool class, reasons for using it, reasons why you shouldn't (added complexities around watchers and events).
* Began work on an experimental Multiplexed client, that would allow multithreaded clients to more effectively share a single connection by making all requests asynchronous behind the scenes, and using a queue to provide a synchronous (blocking) API. 


# vim:ft=markdown:sts=2:sw=2:et
