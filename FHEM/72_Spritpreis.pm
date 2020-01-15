##############################################
# $Id: 72_Spritpreis.pm 0 2017-01-10 12:00:00Z pjakobs $

# v0.0: inital testing
# v0.1: basic functionality for pre-configured Tankerkoenig IDs


package main;
 
use strict;
use warnings;

use Time::HiRes;
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
    $hash->{AttrList}       = "lat lon rad IDs type sortby apikey interval address"." $readingFnAttributes";
    #$hash->{AttrList}       = "IDs type interval"." $readingFnAttributes";
    return undef;
}

sub
Spritpreis_Define($$) {
    #####################################
    #
    # how to define this
    #
    # for Tankerkönig:
    # define <myName> Spritpreis Tankerkoenig <TankerkönigAPI_ID>
    #
    # for Spritpreisrechner.at
    # define <myName> Spritpreis Spritpreisrechner
    #
    #####################################


    my $apiKey;
    my ($hash, $def)=@_;
    my @parts=split("[ \t][ \t]*", $def);
    my $name=$parts[0];
    if(defined $parts[2]){
        if($parts[2] eq "Tankerkoenig"){
            ## 
            if(defined $parts[3]){
                $apiKey=$parts[3];
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
                        Log3 ($hash, 2, "$hash->{name}: error: $result->{message}");
                        return undef;
                    }
                }
                $hash->{helper}->{apiKey}=$apiKey;
                $hash->{helper}->{service}="Tankerkoenig";
            }
            if(AttrVal($hash->{NAME}, "IDs","")){
                #
                # if IDs attribute is defined, populate list of stations at startup
                #
                my $ret=Spritpreis_Tankerkoenig_populateStationsFromAttr($hash);
            }
            #
            # start initial update
            #
            Spritpreis_Tankerkoenig_updateAll($hash);
        } elsif($parts[2] eq "Spritpreisrechner"){
            $hash->{helper}->{service}="Spritpreisrechner";
        }
    }else{
        Log3($hash,2,"$hash->{NAME} Module $parts[1] requires a provider specification. Currently either \"Tankerkoenig\" (for de) or \"Spritpreisrechner\" (for at)");
    }
    return undef;
}

sub
Spritpreis_Undef(@){
    my ($hash,$name)=@_;
    RemoveInternalTimer($hash);
    return undef;
}

sub
Spritpreis_Set(@) {
    my ($hash , $name, $cmd, @args) = @_;
    return "Unknown command $cmd, choose one of update add delete" if ($cmd eq '?');
    Log3($hash, 3,"$hash->{NAME}: get $hash->{NAME} $cmd $args[0]");

    if ($cmd eq "update"){
        if(defined $args[0]){
            if($args[0] eq "all"){
                # removing the timer so we don't get a flurry of requests
                RemoveInternalTimer($hash);
                Spritpreis_Tankerkoenig_updateAll($hash);
            }elsif($args[0] eq "id"){
                if(defined $args[1]){
                    Spritpreis_Tankerkoenig_updatePricesForIDs($hash, $args[1]);
                }else{
                    my $r="update id requires an id parameter!";
                    Log3($hash, 2,"$hash->{NAME} $r");
                    return $r;
                }
            }
        }else{
            #
            # default behaviour if no ID or "all" is given is to update all existing IDs
            #
            Spritpreis_Tankerkoenig_updateAll($hash); 
        }
    }elsif($cmd eq "add"){
        if(defined $args[0]){
            Log3($hash, 4,"$hash->{NAME} add: args[0]=$args[0]");
            if($args[0] eq "id"){
                #
                # add station by providing a single Tankerkoenig ID
                #
                if(defined($args[1])){
                    Spritpreis_Tankerkoenig_GetDetailsForID($hash, $args[1]);
                }else{
                    my $ret="add by id requires a station id";
                    return $ret;
                }
            }
        }else{
            my $ret="add requires id or (some other method here soon)";
            return $ret;
        }
    }elsif($cmd eq "delete"){
        # 
        # not sure how to "remove" readings through the fhem api
        #
    }
    return undef;
}

sub
Spritpreis_Get(@) {
    my ($hash, $name, $cmd, @args) = @_;

    return "Unknown command $cmd, choose one of search test" if ($cmd eq '?');
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
            if($hash->{helper}->{service} eq "Tankerkoenig"){
                my $ret=Spritpreis_Tankerkoenig_GetStationIDsForLocation($hash, @loc);
                return $ret;
            }
        }
    }elsif($cmd eq "test"){
            my $ret=Spritpreis_Tankerkoenig_populateStationsFromAttr($hash);
            return $ret;

    }else{
        return undef;
    } 
    #Spritpreis_Tankerkoenig_GetPricesForLocation($hash);
    #Spritpreis_GetCoordinatesForAddress($hash,"Hamburg, Elbphilharmonie");
    # add price trigger here
    return undef;
}

sub
Spritpreis_Attr(@) {
    my ($cmd, $device, $attrName, $attrVal)=@_;
    my $hash = $defs{$device};

    if ($cmd eq 'set' and $attrName eq 'interval'){
        Spritpreis_updateAll($hash);
    }
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
# generalized functions
# these functions will call the 
# specific functions for the defined
# provider.
#
#####################################

sub
Spritpreis_GetDetailsForID(){
}

sub
Spritpreis_updateAll(@){
    my ($hash)=@_;
    if($hash->{helper}->{service} eq "Tankerkoenig"){
        Spritpreis_Tankerkoenig_updateAll();
    }elsif($hash->{helper}->{service} eq "Spritpreisrechner"){
    }
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
    my $apiKey=$hash->{helper}->{apiKey};
    Log3($hash,4,"$hash->{'NAME'}: apiKey: $apiKey");

    if($apiKey eq "") {
        Log3($hash,3,"$hash->{'NAME'}: please provide a valid apikey, you can get it from https://creativecommons.tankerkoenig.de/#register. This function can't work without it"); 
        my $r="err no APIKEY";
        return $r; 
    }

    my $url="https://creativecommons.tankerkoenig.de/json/list.php?lat=$lat&lng=$lng&rad=$rad&type=$type&apikey=$apiKey"; 
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

#--------------------------------------------------
# sub
# Spritpreis_Tankerkoenig_GetIDs(@){
#     my ($hash) = @_;
#     Log3($hash, 4, "$hash->{NAME} called Spritpreis_Tankerkoenig_updatePricesForIDs");
#     my $IDstring=AttrVal($hash->{NAME}, "IDs","");
#     Log3($hash,4,"$hash->{NAME}: got ID String $IDstring");
#     my @IDs=split(",", $IDstring);
#     my $i=1;
#     my $j=1;
#     my $IDList;
#     do {
#         $IDList=$IDs[0];
#         #
#         # todo hier stimmt was mit den Indizes nicht! 
#         #
#         do {
#             $IDList=$IDList.",".$IDs[$i];
#         }while($j++ < 9 && defined($IDs[$i++]));
#         Spritpreis_Tankerkoenig_updatePricesForIDs($hash, $IDList);
#         Log3($hash, 4,"$hash->{NAME}: Set ending at $i IDList=$IDList");
#         $j=1;
#     }while(defined($IDs[$i]));
#     return undef;
# }
#-------------------------------------------------- 

sub
Spritpreis_Tankerkoenig_populateStationsFromAttr(@){
    #
    # This walks through the IDs Attribute and adds the stations listed there to the station readings list,
    # initially getting full details
    #
    my ($hash) =@_;
    Log3($hash,4, "$hash->{NAME}: called Spritpreis_Tankerkoenig_populateStationsFromAttr ");
    my $IDstring=AttrVal($hash->{NAME}, "IDs","");
    Log3($hash,4,"$hash->{NAME}: got ID String $IDstring");
    my @IDs=split(",", $IDstring);
    my $i;
    do{
        Spritpreis_Tankerkoenig_GetDetailsForID($hash, $IDs[$i]);
    }while(defined($IDs[$i++]));
}

sub
Spritpreis_Tankerkoenig_updateAll(@){
    #
    # this walks through the list of ID Readings and updates the fuel prices for those stations
    # it does this in blocks of 10 as suggested by the Tankerkoenig API
    #
    my ($hash) = @_;
    Log3($hash,4, "$hash->{NAME}: called Spritpreis_Tankerkoenig_updateAll ");
    my $i=1;
    my $j=0;
    my $id;
    my $IDList;
    do {
        $IDList=ReadingsVal($hash->{NAME}, $j."_id", "");
        while($j++<9 && ReadingsVal($hash->{NAME}, $i."_id", "") ne "" ){
            Log3($hash, 5, "$hash->{NAME}: i: $i, j: $j, id: ".ReadingsVal($hash->{NAME}, $i."_id", "") );
            $IDList=$IDList.",".ReadingsVal($hash->{NAME}, $i."_id", "");
            $i++;
        }
        if($IDList ne ""){
            Spritpreis_Tankerkoenig_updatePricesForIDs($hash, $IDList);
            Log3($hash, 4,"$hash->{NAME}(update all): Set ending at $i IDList=$IDList");
        }
        $j=1;
    }while(ReadingsVal($hash->{NAME}, $i."_id", "") ne "" );
    Log3($hash, 4, "$hash->{NAME}: updateAll set timer for ".(gettimeofday()+AttrVal($hash->{NAME},"interval",15)*60)." delay ".(AttrVal($hash->{NAME},"interval", 15)*60));
    InternalTimer(gettimeofday()+AttrVal($hash->{NAME}, "interval",15)*60, "Spritpreis_Tankerkoenig_updateAll",$hash);
    return undef;
}

sub
Spritpreis_Tankerkoenig_GetDetailsForID(@){
    # 
    # This queries the Tankerkoenig API for the details for a specific ID
    # It does not verify the provided ID
    # The parser function is responsible for handling the response
    #
    my ($hash, $id)=@_;
    my $apiKey=$hash->{helper}->{apiKey};
    if($apiKey eq "") {
        Log3($hash,3,"$hash->{'NAME'}: please provide a valid apikey, you can get it from https://creativecommons.tankerkoenig.de/#register. This function can't work without it"); 
        my $r="err no APIKEY";
        return $r;
    }
    my $url="https://creativecommons.tankerkoenig.de/json/detail.php?id=".$id."&apikey=$apiKey";
    Log3($hash, 4,"$hash->{NAME}: called $url");
    my $param={
        url     =>  $url,
        hash    =>  $hash,
        timeout =>  10,
        method  =>  "GET",
        header  =>  "User-Agent: fhem\r\nAccept: application/json",
        parser  =>  \&Spritpreis_Tankerkoenig_ParseDetailsForID,
        callback=>  \&Spritpreis_callback
    };
    HttpUtils_NonblockingGet($param);
    return undef;
}

sub
Spritpreis_Tankerkoenig_updatePricesForIDs(@){
    # 
    # This queries the Tankerkoenig API for an update on all prices. It takes a list of up to 10 IDs.
    # It will not verify the validity of those IDs nor will it check that the number is 10 or less
    # The parser function is responsible for handling the response
    #
    my ($hash, $IDList) = @_;
    my $apiKey=$hash->{helper}->{apiKey};
    my $url="https://creativecommons.tankerkoenig.de/json/prices.php?ids=".$IDList."&apikey=$apiKey";
    Log3($hash, 4,"$hash->{NAME}: called $url");
    my $param={
        url     =>  $url,
        hash    =>  $hash,
        timeout =>  10,
        method  =>  "GET",
        header  =>  "User-Agent: fhem\r\nAccept: application/json",
        parser  =>  \&Spritpreis_Tankerkoenig_ParsePricesForIDs,
        callback=>  \&Spritpreis_callback
    };
    HttpUtils_NonblockingGet($param);
    return undef;
}

sub
Spritpreis_Spritpreisrechner_updatePricesForLocation(@){
    #
    # for the Austrian Spritpreisrechner, there's not concept of IDs. The only method
    # is to query for prices by location which will make it difficult to follow the 
    # price trend at any specific station.
    #
    my ($hash)=@_;    
    my $url="http://www.spritpreisrechner.at/espritmap-app/GasStationServlet";
    my $lat=AttrVal($hash->{'NAME'}, "lat",0);
    my $lng=AttrVal($hash->{'NAME'}, "lon",0);

    my $param={
        url     => $url,
        timeout => 1,
        method  => "POST",
        header  => "User-Agent: fhem\r\nAccept: application/json",
        data    => {
            "",
            "DIE",
            "15.409674251128",
            "47.051201316374",
            "15.489496791403",
            "47.074588294516"
        }
    };
    my ($err,$data)=HttpUtils_BlockingGet($param);
    Log3($hash,5,"$hash->{'NAME'}: Dumper($data)");
    return undef;
}

sub
Spritpreis_Tankerkoenig_GetStationIDsForLocation(@){
   #
   # This is currently not being used. The idea is to provide a lat/long location and a radius and have
   # the stations within this radius are presented as a list and, upon selecting them, will be added
   # to the readings list
   #
   my ($hash,@location) = @_;

   # my $lat=AttrVal($hash->{'NAME'}, "lat",0);
   # my $lng=AttrVal($hash->{'NAME'}, "lon",0);
   my $rad=AttrVal($hash->{'NAME'}, "rad",5);
   my $type=AttrVal($hash->{'NAME'}, "type","all");
   # my $sort=AttrVal($hash->{'NAME'}, "sortby","price"); 
   my $apiKey=$hash->{helper}->{apiKey};

   my ($lat, $lng, $formattedAddress)=@location;

   my $result;

   if($apiKey eq "") {
       Log3($hash,3,"$hash->{'NAME'}: please provide a valid apikey, you can get it from https://creativecommons.tankerkoenig.de/#register. This function can't work without it"); 
       my $r="err no APIKEY";
       return $r;
   }
   my $url="https://creativecommons.tankerkoenig.de/json/list.php?lat=$lat&lng=$lng&rad=$rad&type=$type&apikey=$apiKey"; 

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
                            "+add+id+" . 
                            $station->{id} . 
                            ">";
                $ret=$ret . $station->{name} . "</td><td>" . $station->{place} . "</td><td>" . $station->{street} . " " . $station->{houseNumber} . "</td></tr>";
            }
            $ret=$ret . "</table>";
            Log3($hash,2,"$hash->{NAME}: ############# ret: $ret");
            return $ret;
        }         
    }else {
        Log3 ($hash, 4, "$hash->{NAME}: something's very odd");
    }
    return $data; 
    # InternalTimer(gettimeofday()+AttrVal($hash->{NAME}, "interval",15)*60, "Spritpreis_Tankerkoenig_GetPricesForLocation",$hash);
    return undef;
}

#####################################
#
# functions to handle responses
#
#####################################

sub
Spritpreis_callback(@) {
    #
    # the generalized callback function. This should check all the general API errors and 
    # handle them centrally, leaving the parser functions to handle response specific errors
    #
    my ($param, $err, $data) = @_;
    my ($hash) = $param->{hash};
 
    # TODO generic error handling
    #Log3($hash, 5, "$hash->{NAME}: received callback with $data");
    # do the result-parser callback
    if ($err){
        Log3($hash, 4, "$hash->{NAME}: error fetching information: $err");
        return undef;
    }
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
Spritpreis_Tankerkoenig_ParseDetailsForID(@){
    #
    # this parses the response generated by the query Spritpreis_Tankerkoenig_GetDetailsForID
    # The response will contain the ID for a single station being, so no need to go through
    # multiple parts here. It will work whether or not that ID is currently already in the list
    # of readings. If it is, the details will be updated, if it is not, the new station will be 
    # added at the end of the list
    #
    my ($hash, $err, $data)=@_;
    my $result;

    if($data){
        Log3($hash, 4, "$hash->{NAME}: got StationDetail reply");
        Log3($hash, 5, "$hash->{NAME}: got data $data\n\n\n");

        eval { $result = JSON->new->utf8(1)->decode($data); };
        if ($@) {
            Log3 ($hash, 4, "$hash->{NAME}: error decoding response $@");
        } else {
            my $i=0;
            my $station = $result->{station};
            while(ReadingsVal($hash->{NAME},$i."_id",$station->{id}) ne $station->{id}) 
            {
                #
                # this loop iterates through the readings until either an id is equal to the current
                # response $station->{id} or, if no id is, it will come up with the default which is set 
                # to $station->{id}, thus it will be added
                #
                $i++;
            }
            readingsBeginUpdate($hash);

            readingsBulkUpdate($hash,$i."_name",$station->{name});
            my @types=("e5", "e10", "diesel");
            foreach my $type (@types){
                Log3($hash,4,"$hash->{NAME}: checking type $type");
                if(defined($station->{$type})){
                    if(ReadingsVal($hash->{NAME}, $i."_".$type."_trend",0)!=0){
                        my $p=ReadingsVal($hash->{NAME}, $i."_".$type."_price",0);
                        Log3($hash,4,"$hash->{NAME}:parseDetailsForID $type price old: $p");
                        if($p>$station->{$type}){
                            readingsBulkUpdate($hash,$i."_".$type."_trend","fällt");
                            Log3($hash,4,"$hash->{NAME}:parseDetailsForID trend: fällt"); 
                        }elsif($p < $station->{$type}){
                            readingsBulkUpdate($hash,$i."_".$type."_trend","steigt");
                            Log3($hash,4,"$hash->{NAME}:parseDetailsForID trend: konstant"); 
                        }else{
                        }
                        readingsBulkUpdate($hash,$i."_".$type."_price",$station->{$type})
                    }
                }
            }
            readingsBulkUpdate($hash,$i."_place",$station->{place});
            readingsBulkUpdate($hash,$i."_street",$station->{street}." ".$station->{houseNumber});
            readingsBulkUpdate($hash,$i."_distance",$station->{dist});
            readingsBulkUpdate($hash,$i."_brand",$station->{brand});
            readingsBulkUpdate($hash,$i."_lat",$station->{lat});
            readingsBulkUpdate($hash,$i."_lon",$station->{lng});
            readingsBulkUpdate($hash,$i."_id",$station->{id});
            readingsBulkUpdate($hash,$i."_isOpen",$station->{isOpen});
          
            readingsEndUpdate($hash,1);
        } 
    }
}

sub
Spritpreis_Tankerkoenig_ParsePricesForIDs(@){
    #
    # This parses the response to Spritpreis_Tankerkoenig_updatePricesForIDs 
    # this response contains price updates for the requested stations listed by ID
    # since we don't keep a context between the API request and the response, 
    # in order to update the correct readings, this routine has to go through the
    # readings list and make sure it does find matching IDs. It will not add new
    # stations to the list
    #
    my ($hash, $err, $data)=@_;
    my $result;

     if($err){
        Log3($hash, 4, "$hash->{NAME}: error fetching information");
    } elsif($data){
        Log3($hash, 4, "$hash->{NAME}: got PricesForLocation reply");
        Log3($hash, 5, "$hash->{NAME}: got data $data\n\n\n");

        eval {
            $result = JSON->new->utf8(1)->decode($data);
        };
        if ($@) {
            Log3 ($hash, 4, "$hash->{NAME}: error decoding response $@");
        } else {
            my ($stations) = $result->{prices};
            Log3($hash, 5, "$hash->{NAME}: stations:".Dumper($stations));
            #
            # the return value is keyed by stations, therefore, I'll have 
            # to fetch the stations from the existing readings and run 
            # through it along those ids.
            #
            my $i=0;
            while(ReadingsVal($hash->{NAME}, $i."_id", "") ne "" ){
                my $id=ReadingsVal($hash->{NAME}, $i."_id", ""); 
                Log3($hash, 4, "$hash->{NAME}: checking ID $id");
                if(defined($stations->{$id})){
                    Log3($hash, 4, "$hash->{NAME}: updating readings-set $i (ID $id)" );
                    Log3($hash, 5, "$hash->{NAME} Update set:\nprice: $stations->{$id}->{price}\ne5: $stations->{$id}->{e5}\ne10: $stations->{$id}->{e10}\ndiesel: $stations->{$id}->{diesel}\n");
                    readingsBeginUpdate($hash);
                    my @types=("e5", "e10", "diesel");
                    foreach my $type (@types){
                        Log3($hash, 4, "$hash->{NAME} ParsePricesForIDs checking type $type");
                        if(defined($stations->{$id}->{$type})){
                            Log3($hash, 4, "$hash->{NAME} ParsePricesForIDs updating type $type");
                            #if(ReadingsVal($hash->{NAME}, $i."_".$type."_trend","") ne ""){
                                my $p=ReadingsVal($hash->{NAME}, $i."_".$type."_price",0);
                                Log3($hash,4,"$hash->{NAME}:parseDetailsForID $type price old: $p");
                                if($p>$stations->{$id}->{$type}){
                                    readingsBulkUpdate($hash,$i."_".$type."_trend","fällt");
                                }elsif($p < $stations->{$id}->{$type}){
                                    readingsBulkUpdate($hash,$i."_".$type."_trend","steigt");
                                }else{
                                }
                                #}
                            readingsBulkUpdate($hash,$i."_".$type."_price",$stations->{$id}->{$type})
                        }
                    }


                    readingsBulkUpdate($hash,$i."_isOpen",$stations->{$id}->{status});
                    
                    readingsEndUpdate($hash, 1);
                }
                $i++;
            }
        }
    }
    return undef;
}

sub
Spritpreis_Tankerkoening_ParseStationIDsForLocation(@){
    my ($hash, $err, $data)=@_;
    my $result;

    Log3($hash,5,"$hash->{NAME}: ParsePricesForLocation has been called with err $err and data $data");

    if($err){
        Log3($hash, 4, "$hash->{NAME}: error fetching information");
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
            my $ret="<html><form action=fhem/cmd?set ".$hash->{NAME}." station method='get'><select multiple name='id'>";
            foreach (@{$stations}){
                (my $station)=$_;

                #Log3($hash, 5, "$hash->{NAME}: Station hash:".Dumper($station));
                Log3($hash, 2, "Name: $station->{name}, id: $station->{id}");
                $ret=$ret."<option value=".$station->{id}.">".$station->{name}." ".$station->{place}." ".$station->{street}." ".$station->{houseNumber}."</option>";
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
