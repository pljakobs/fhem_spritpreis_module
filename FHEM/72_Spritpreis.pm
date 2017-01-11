##############################################
# $Id: 72_Spritpreis.pm 0 2017-01-10 12:00:00Z pjakobs $

# v0.0: inital testing
#


package main;
 
use strict;
use warnings;

use Time::HiRes;
use Time::HiRes qw(usleep nanosleep);
use Time::HiRes qw(time);
use JSON::XS;
use URI::URL;
use Data::Dumper;
require "HttpUtils.pm";

$Data::Dumper::Indent = 1;
$Data::Dumper::Sortkeys = 1;

#####################################
#
# fhem skeleton functions
#
#####################################

sub
Spritpreis_Initialize(@) {
    my ($hash) = @_;

    $hash->{DefFn}          = 'Spritpreis_Define';
    $hash->{UndefFn}        = 'Spritpreis_Undef';
    $hash->{ShutdownFn}     = 'Spritpreis_Undef';
    $hash->{SetFn}          = 'Spritpreis_Set';
    $hash->{GetFn}          = 'Spritpreis_Get';
    $hash->{AttrFn}         = 'Spritpreis_Attr';
    $hash->{NotifyFn}       = 'Spritpreis_Notify';
    $hash->{ReadFn}         = 'Spritpreis_Read';
    $hash->{AttrList}       = "lat lon rad type sortby apikey interval address"." $readingFnAttributes";
    return undef;
}

sub
Spritpreis_Define($$) {

    my ($hash, $def)=@_;
    my @parts=split("[ \t][ \t]*", $def);
    my $name=$parts[0];
    Spritpreis_Tankerkoenig_GetPricesForLocation($hash);
    InternalTimer(gettimeofday()+AttrVal($hash->{NAME}, "interval",15)*60, "Spritpreis_Tankerkoenig_GetPricesForLocation",$hash);
    return undef;
}

sub
Spritpreis_Undef(@){
    return undef;
}

sub
Spritpreis_Set(@) {
    return undef;
}

sub
Spritpreis_Get(@) {
    my ($hash, $name, $cmd, @args) = @_;
    Spritpreis_Tankerkoenig_GetPricesForLocation($hash);
    Spritpreis_GetCoordinatesForAddress($hash,"Ratzeburg, Strängnäsweg 20");
    # add price trigger here
    return undef;
}

sub
Spritpreis_Attr(@) {
    return undef;
}

sub
Spritpreis_Notify(@) {
    return undef;
}

sub
Spritpreis_Read(@) {
    return undef;
}

#####################################
#
# functions to create requests
#
#####################################

sub
Spritpreis_Tankerkoenig_GetIDsForLocation(@){
    my ($hash) = @_;
    my $lat=AttrVal($hash->{'NAME'}, "lat",0);
    my $lng=AttrVal($hash->{'NAME'}, "lon",0);
    my $rad=AttrVal($hash->{'NAME'}, "rad",5);
    my $type=AttrVal($hash->{'NAME'}, "type","diesel");
    my $sort=AttrVal($hash->{'NAME'}, "sortby","price");
    my $apikey=AttrVal($hash->{'NAME'}, "apikey","");

    if($apikey eq "") {
        Log3($hash,3,"$hash->{'NAME'}: please provide a valid apikey, you can get it from https://creativecommons.tankerkoenig.de/#register. This function can't work without it"); 
        return "err no APIKEY";
    }

    my $url="https://creativecommons.tankerkoenig.de/json/list.php?lat=$lat&lng=$lng&rad=$rad&type=$type&sort=$sort&apikey=$apikey"; 
    my $param = {
        url      => $url,
        timeout  => 2,
        hash     => $hash,
        method   => "GET",
        header   => "User-Agent: fhem\r\nAccept: application/json",
        parser   => \&Spritpreis_ParseIDsForLocation,
        callback => \&Spritpreis_callback
    };
    HttpUtils_NonblockingGet($param);

    return undef;
}

sub
Spritpreis_Tankerkoenig_GetPricesForIDs(@){
    my ($hash) = @_;

    return undef;
}

sub
Spritpreis_Tankerkoenig_GetPricesForLocation(@){
   my ($hash) = @_;

   my $lat=AttrVal($hash->{'NAME'}, "lat",0);
   my $lng=AttrVal($hash->{'NAME'}, "lon",0);
   my $rad=AttrVal($hash->{'NAME'}, "rad",5);
   my $type=AttrVal($hash->{'NAME'}, "type","diesel");
   my $sort=AttrVal($hash->{'NAME'}, "sortby","price");
   my $apikey=AttrVal($hash->{'NAME'}, "apikey","");

   if($apikey eq "") {
       Log3($hash,3,"$hash->{'NAME'}: please provide a valid apikey, you can get it from https://creativecommons.tankerkoenig.de/#register. This function can't work without it"); 
       return "err no APIKEY";
   }
   my $url="https://creativecommons.tankerkoenig.de/json/list.php?lat=$lat&lng=$lng&rad=$rad&type=$type&sort=$sort&apikey=$apikey"; 

   Log3($hash, 4,"$hash->{NAME}: sending request with url $url");
   
   my $param= {
       url      => $url,
       hash     => $hash,
       timeout  => 30,
       method   => "GET",
       header   => "User-Agent: fhem\r\nAccept: application/json",
       parser   => \&Spritpreis_ParsePricesForLocation,
       callback => \&Spritpreis_callback
    };
    HttpUtils_NonblockingGet($param);
    InternalTimer(gettimeofday()+AttrVal($hash->{NAME}, "interval",15)*60, "Spritpreis_Tankerkoenig_GetPricesForLocation",$hash);
    return undef;
}

#####################################
#
# functions to handle responses
#
#####################################

sub
Spritpreis_callback(@) {
     my ($param, $err, $data) = @_;
     my ($hash) = $param->{hash};
 
     # TODO generic error handling
     #Log3($hash, 5, "$hash->{NAME}: received callback with $data");
     # do the result-parser callback
     my $parser = $param->{parser};
     #Log3($hash, 4, "$hash->{NAME}: calling parser $parser with err $err and data $data");
     &$parser($hash, $err, $data);
 
     # Do readings update
 
     if( $err || $err ne ""){
         Log3 ($hash, 3, "$hash->{NAME} Readings NOT updated, received Error: ".$err);
     }
   return undef;
 }

sub 
Spritpreis_ParseIDsForLocation(@){
    return undef;
}

sub
Spritpreis_ParsePricesForLocation(@){
    my ($hash, $err, $data)=@_;
    my $result;

    Log3($hash,5,"$hash->{NAME}: ParsePricesForLocation has been called with err $err and data $data");

    if($err){
        Log3($hash, 4, "$hash->{NAME}: error fetching nformation");
    } elsif($data){
        Log3($hash, 4, "$hash->{NAME}: got PricesForLocation reply");
        Log3($hash, 5, "$hash->{NAME}: got data $data\n\n\n");

        eval {
            $result = JSON->new->utf8(1)->decode($data);
        };
        if ($@) {
            Log3 ($hash, 4, "$hash->{NAME}: error decoding response $@");
        } else {
            my ($stations) = $result->{stations};
            #Log3($hash, 5, "$hash->{NAME}: stations:".Dumper($stations));
            readingsBeginUpdate($hash);
            foreach (@{$stations}){
                (my $station)=$_;

                #Log3($hash, 5, "$hash->{NAME}: Station hash:".Dumper($station));
                Log3($hash, 2, "Name: $station->{name}, id: $station->{id}\n");
                my $number=0;
                
                # make sure we update a record with an existign id or create a new one for a new id
                while(ReadingsVal($hash->{NAME},$number."_id",$station->{id}) ne $station->{id}) 
                {
                    $number++;
                }
                readingsBulkUpdate($hash,$number."_name",$station->{name});
                readingsBulkUpdate($hash,$number."_price",$station->{price});
                readingsBulkUpdate($hash,$number."_place",$station->{place});
                readingsBulkUpdate($hash,$number."_street",$station->{street}." ".$station->{houseNumber});
                readingsBulkUpdate($hash,$number."_distance",$station->{dist});
                readingsBulkUpdate($hash,$number."_brand",$station->{brand});
                readingsBulkUpdate($hash,$number."_lat",$station->{lat});
                readingsBulkUpdate($hash,$number."_lon",$station->{lng});
                readingsBulkUpdate($hash,$number."_id",$station->{id});
                readingsBulkUpdate($hash,$number."_isOpen",$station->{isOpen});
            }
            readingsEndUpdate($hash,1);
        }         
    }else {
        Log3 ($hash, 4, "$hash->{NAME}: something's very odd");
    }
    return $data; 
}

sub
Spritpreis_ParsePricesForIDs(@){
}
#####################################
#
# geolocation functions
#
#####################################

sub
Spritpreis_GetCoordinatesForAddress(@){
    my ($hash, $address)=@_;
    
    my $url=new URI::URL 'https://maps.google.com/maps/api/geocode/json';
    $url->query_form("address",$address);
    Log3($hash, 3, "$hash->{NAME}: request URL: ".$url);

    my $param= {
    url      => $url,
    hash     => $hash,
    timeout  => 30,
    method   => "GET",
    header   => "User-Agent: fhem\r\nAccept: application/json",
    parser   => \&Spritpreis_ParseCoordinatesForAddress,
    callback => \&Spritpreis_callback
    };
    HttpUtils_NonblockingGet($param);
    return undef;
}

sub
Spritpreis_ParseCoordinatesForAddress(@){
    my ($hash, $err, $data)=@_;
    my $result;

    Log3($hash,5,"$hash->{NAME}: ParseCoordinatesForAddress has been called with err $err and data $data");

    if($err){
        Log3($hash, 4, "$hash->{NAME}: error fetching nformation");
    } elsif($data){
        Log3($hash, 4, "$hash->{NAME}: got CoordinatesForAddress reply");
        Log3($hash, 5, "$hash->{NAME}: got data $data\n\n\n");

        eval {
            $result = JSON->new->utf8(1)->decode($data);
        };
        if ($@) {
            Log3 ($hash, 4, "$hash->{NAME}: error decoding response $@");
        } else {
            my $lat=$result->{results}->[0]->{geometry}->{location}->{lat};
            my $lon=$result->{results}->[0]->{geometry}->{location}->{lng};

            Log3($hash,3,"$hash->{NAME}: got coordinates for address as lat: $lat, lon: $lon");
            # readingsBeginUpdate($hash);
            
            # readingsEndUpdate($hash,1);
        }         
    }else {
        Log3 ($hash, 4, "$hash->{NAME}: something is very odd");
    }
    return $data; 
}
       
#####################################
#
# helper functions
#
#####################################
1;
