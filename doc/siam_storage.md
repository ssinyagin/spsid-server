Storing SIAM objects in SPSID
=============================


Object attributes
-----------------

The following attributes are inherited from corresponding `spsid.*`
attributes in SPSID objects:

* `siam.object.id` equals to `spsid.object.id`
* `siam.object.class` equals to `spsid.object.class`
* `siam.object.container` equals to `spsid.object.container`


The attribute `siam.object.complete`, if undefined, defaults to 1.



The root object
---------------

The root SIAM object is stored in SPSID, and it's the only object with
the attribute `spsid.siam.root`, and its value is always 1.

The root object has `NIL` as the container ID.

