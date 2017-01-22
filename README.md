# Spritpreismodule.pm
an experimental module to provide fuel price updates from various apis
my main motivation to start this is to gain some experience writing fhem modules from scratch.
it's not primarily thought of as a production ready module and things may vary. a lot.

### Installation
for now, copy 72_Spritpreis.pm to /opt/fhem/FHEM 
then restart fhem

### Contributions
Contributions are welcome

### Branches
* Master: whatever I deem slightly useful
* Develop: a slightly useful branch (not all functions may be working) that contributors should fork and provide their pull requests to


### ToDo:
General architecture:
There are several providers of fuel price services in various countries. This module should provide "branded" subs for those providers (like Spritpreis_Tankerkoenig_getPricesForLocation(@) etc). The module itself would be configured with 
define Benzinpreis Spritpreis <provider> <additional provider relevant parameters>

[ ] the Tankerkönig configurator spits out a pretty useful bit of json, it would be great to just use that to get the IDs


### Links

* Tankerkönig: https://creativecommons.tankerkoenig.de/ (DE, API for location and ID driven search)
* Spritpreisrecher: http://www.spritpreisrechner.at (AT, API for rectangular search are, possibly more)
    * Examples for Spritpreisrechner:  https://blog.muehlburger.at/2011/08/spritpreisrechner-at-apps-entwickeln and http://gregor-horvath.com/spritpreis.html


