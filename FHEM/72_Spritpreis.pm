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
    $hash->{AttrList}       = "IDs type interval"." $readingFnAttributes";
    return undef;
}

sub
Spritpreis_Define($$) {

    my $apiKey;
    my ($hash, $def)=@_;
    my @parts=split("[ \t][ \t]*", $def);
    my $name=$parts[0];
    if(defined $parts[2]){
        $apiKey=$parts[2];
    }else{
        Log3 ($hash, 2, "$hash->{NAME} Module $parts[1] requires a valid apikey");
        return undef;
    }

    my $result;
    my $url="https://creativecommons.tankerkoenig.de/json/prices.php?ids=12121212-1212-1212-1212-121212121212&apikey=".$apiKey; 
    
    my $param= {
    url      => $url,
    timeout  => 1,
    method   => "GET",
    header   => "User-Agent: fhem\r\nAccept: application/json",
    };
    
    my ($err, $data)=HttpUtils_BlockingGet($param);

    if ($err){
        Log3($hash,2,"$hash->{NAME}: Error verifying APIKey: $err");
        return undef;
    }else{
        eval {
            $result = JSON->new->utf8(1)->decode($data);
        };
        if ($@) {
            Log3 ($hash, 4, "$hash->{NAME}: error decoding response $@");
        } else {
            if ($result->{ok} ne "true"){
                Log3 ($hash, 2, "$hash->{name}: error: $result-{message}");
                return undef;
            }
        }
        $hash->{helper}->{apiKey}=$apiKey;
    }
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

    return "Unknown command $cmd, choose one of search" if ($cmd eq '?');
    Log3($hash, 3,"$hash->{NAME}: get $hash->{NAME} $cmd $args[0]");

    if ($cmd eq "search"){
        my $str='';
        my $i=0;
        while($args[$i++]){
            $str=$str." ".$args[$i];
        }
        Log3($hash,4,"$hash->{NAME}: search string: $str");
        my @loc=Spritpreis_GetCoordinatesForAddress($hash, $str);
        my ($lat, $lng, $str)=@loc;
        if($lat==0 && $lng==0){
            return $str;
        }else{
            my $ret=Spritpreis_GetStationIDsForLocation($hash, @loc);
            return $ret;
        }
    }
    #Spritpreis_Tankerkoenig_GetPricesForLocation($hash);
    #Spritpreis_GetCoordinatesForAddress($hash,"Hamburg, Elbphilharmonie");
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
Spritpreis_Tankerkoenig_UpdatePricesForIDs(@){
    my ($hash) = @_;

    my @IDs=split(",", attrVal($hash,"IDs",""));
    my $i=0;
    my $j=0;
    my $IDList;
    do {
        $IDList="";
        do {
            $IDList=$IDList.",".$IDs[$i];
        }while($j++ < 10 && defined($IDs[$i++]));
        Spritpreis_Tankerkoenig_UpdatePricesForIDs($hash, $IDList);
        Log3($hash, 4,"$hash->{NAME}: IDList=$IDList");
        $j=0;
    }while(defined($IDs[$i]));
    Log3($hash, 4,"$hash->{NAME}: IDList=$IDList");
    Spritpreis_Tankerkoenig_UpdatePricesForIDs($hash, $IDList) if ($IDList ne "");
    return undef;
}

sub
Spritpreis_Tankerkoenig_GetDetailsForIDs(@){
    my ($hash, $id)=@_;


sub
Spritpreis_GetStationIDsForLocation(@){
   my ($hash,@location) = @_;

   # my $lat=AttrVal($hash->{'NAME'}, "lat",0);
   # my $lng=AttrVal($hash->{'NAME'}, "lon",0);
   my $rad=AttrVal($hash->{'NAME'}, "rad",5);
   my $type=AttrVal($hash->{'NAME'}, "type","diesel");
   my $sort=AttrVal($hash->{'NAME'}, "sortby","price");
   my $apikey=AttrVal($hash->{'NAME'}, "apikey","");

   my ($lat, $lng, $formattedAddress)=@location;

   my $result;

   if($apikey eq "") {
       Log3($hash,3,"$hash->{'NAME'}: please provide a valid apikey, you can get it from https://creativecommons.tankerkoenig.de/#register. This function can't work without it"); 
       return "err no APIKEY";
   }
   my $url="https://creativecommons.tankerkoenig.de/json/list.php?lat=$lat&lng=$lng&rad=$rad&type=$type&sort=$sort&apikey=$apikey"; 

   Log3($hash, 4,"$hash->{NAME}: sending request with url $url");
   
   my $param= {
       url      => $url,
       hash     => $hash,
       timeout  => 1,
       method   => "GET",
       header   => "User-Agent: fhem\r\nAccept: application/json",
    };
    my ($err, $data) = HttpUtils_BlockingGet($param);

    if($err){
        Log3($hash, 4, "$hash->{NAME}: error fetching nformation");
    } elsif($data){
        Log3($hash, 4, "$hash->{NAME}: got data");
        Log3($hash, 5, "$hash->{NAME}: got data $data\n\n\n");

        eval {
            $result = JSON->new->utf8(1)->decode($data);
        };
        if ($@) {
            Log3 ($hash, 4, "$hash->{NAME}: error decoding response $@");
        } else {
            my @headerHost = grep /Host/, @FW_httpheader;
            $headerHost[0] =~ s/Host: //g;

            my ($stations) = $result->{stations};
            my $ret="<html><p><h3>Stations for Address</h3></p><p><h2>$formattedAddress</h2></p><table><tr><td>Name</td><td>Ort</td><td>Straße</td></tr>";
            foreach (@{$stations}){
                (my $station)=$_;

                Log3($hash, 2, "Name: $station->{name}, id: $station->{id}");
                $ret=$ret . "<tr><td><a href=http://" . 
                            $headerHost[0] . 
                            "/fhem?cmd=set+" . 
                            $hash->{NAME} . 
                            "+add+station+" . 
                            $station->{id} . 
                            ">";
                $ret=$ret . $station->{name} . "</td><td>" . $station->{place} . "</td><td>" . $station->{street} . " " . $station->{houseNumber} . "</td></tr>";
                #$ret=$ret."<option value=".$station->{id}.">".$station->{name}." ".$station->{place}." ".$station->{street}." ".$station->{houseNumber}."</option>";
            }
            $ret=$ret . "</table>";
            #$ret=$ret."<button type='submit'>submit</button></form></html>";
            Log3($hash,2,"$hash->{NAME}: ############# ret: $ret");
            return $ret;
        }         
    }else {
        Log3 ($hash, 4, "$hash->{NAME}: something's very odd");
    }
    return $data; 
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
Spritpreis_ParseStationIDsForLocation(@){
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
            # readingsBeginUpdate($hash);
            my $ret="<html><form action=fhem/cmd?set ".$hash->{NAME}." station method='get'><select multiple name='id'>";
            foreach (@{$stations}){
                (my $station)=$_;

                #Log3($hash, 5, "$hash->{NAME}: Station hash:".Dumper($station));
                Log3($hash, 2, "Name: $station->{name}, id: $station->{id}");
                # my $number=0;
                $ret=$ret."<option value=".$station->{id}.">".$station->{name}." ".$station->{place}." ".$station->{street}." ".$station->{houseNumber}."</option>";
                # make sure we update a record with an existign id or create a new one for a new id
                # while(ReadingsVal($hash->{NAME},$number."_id",$station->{id}) ne $station->{id}) 
                # {
                #     $number++;
                # }
                # readingsBulkUpdate($hash,$number."_name",$station->{name});
                # readingsBulkUpdate($hash,$number."_price",$station->{price});
                # readingsBulkUpdate($hash,$number."_place",$station->{place});
                # readingsBulkUpdate($hash,$number."_street",$station->{street}." ".$station->{houseNumber});
                # readingsBulkUpdate($hash,$number."_distance",$station->{dist});
                # readingsBulkUpdate($hash,$number."_brand",$station->{brand});
                # readingsBulkUpdate($hash,$number."_lat",$station->{lat});
                # readingsBulkUpdate($hash,$number."_lon",$station->{lng});
                # readingsBulkUpdate($hash,$number."_id",$station->{id});
                # readingsBulkUpdate($hash,$number."_isOpen",$station->{isOpen});
            }
            # readingsEndUpdate($hash,1);
            $ret=$ret."<button type='submit'>submit</button></html>";
            Log3($hash,2,"$hash->{NAME}: ############# ret: $ret");
            return $ret;
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
    
    my $result;

    my $url=new URI::URL 'https://maps.google.com/maps/api/geocode/json';
    $url->query_form("address",$address);
    Log3($hash, 3, "$hash->{NAME}: request URL: ".$url);

    my $param= {
    url      => $url,
    timeout  => 1,
    method   => "GET",
    header   => "User-Agent: fhem\r\nAccept: application/json",
    };
    my ($err, $data)=HttpUtils_BlockingGet($param);

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
            if ($result->{status} eq "ZERO_RESULTS"){
                return(0,0,"error: could not find address");
            }else{
                my $lat=$result->{results}->[0]->{geometry}->{location}->{lat};
                my $lon=$result->{results}->[0]->{geometry}->{location}->{lng};
                my $formattedAddress=$result->{results}->[0]->{formatted_address};

                Log3($hash,3,"$hash->{NAME}: got coordinates for address as lat: $lat, lon: $lon");
                return ($lat, $lon, $formattedAddress);
            }
        }         
    }else {
        Log3 ($hash, 4, "$hash->{NAME}: something is very odd");
    }
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
            return ($lat, $lon);
        }         
    }else {
        Log3 ($hash, 4, "$hash->{NAME}: something is very odd");
    }
    return undef; 
}
       
#####################################
#
# helper functions
#
#####################################
1;
