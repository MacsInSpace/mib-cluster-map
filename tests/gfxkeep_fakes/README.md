Stand-ins for the stock AU57x (K3663, MU1425 lsd.jxe) classes that
ClusterMapGfxKeep.jar reaches, with the same names, access and signatures
(public classes, public methods, interface-typed models and framework), for
tests/gfxkeep_logic_test.sh. `Calls.LOG` records what the jar did. Behaviour
is reduced to what the jar depends on: model 51 is the cockpit nav tab view
(2 MAP, 3 KDK, 4 COMPASS), getNewValidViewMode turns COMPASS into KDK while a
route runs, switchViewMode records the view it was asked for.
