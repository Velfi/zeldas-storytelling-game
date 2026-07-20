# ExpansionPack v1

An `ExpansionPack v1` is a data-and-assets archive that contributes qualified
catalog records to the shared editor and runtime. It cannot contain executable
plugins. Every pack declares a stable ID, a unique namespace, an exact semantic
version, compatible engine range, contributed catalogs, optional engine
capability declarations, redistribution policy, and per-file SHA-256 integrity.

Catalog IDs have the form `namespace:local_id`. `core` is reserved for built-in
content. Installed versions coexist under `Expansions/<id>/<version>` and an
atomic profile records enabled identities. Enabling rebuilds the catalog
registry consumed by Build Mode. Duplicate namespaces and qualified IDs are
rejected rather than resolved by load order.

```sh
make expansion-export OUT=build/art-deco.expansion
make expansion-inspect PACKAGE=build/art-deco.expansion
make expansion-install PACKAGE=build/art-deco.expansion
make expansion-disable EXPANSION=art-deco@1.2.3
```
