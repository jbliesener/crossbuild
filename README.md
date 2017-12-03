# crossbuild
Docker container for cross-building X-Plane plugins

This docker container was derived from multiarch/crossbuild and extended to support 
openssl 1.0.2m as a static library on windows and osx, as well as the gnu regular
expression library for windows.

Furthermore, some of the required libraries for linux are added.

TODO: Make Linux 32 bit compile work.
