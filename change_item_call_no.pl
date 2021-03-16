#!/usr/bin/perl
use strict;
use warnings;

use Text::CSV;
use LWP;
use Data::Dumper;
use XML::LibXML;
use Time::Piece;
 
my $csv_file = $ARGV[0] or die "1. Argument: CSV-File mit Input\n";
my $log_file = $ARGV[1] or die "2. Argument: CSV-File mit Output\n";
my $key_file = $ARGV[2] or die "3. Argument: Textfile mit API_KEY\n";
my $mode = $ARGV[3] or die "4. Argument: Inputfile-Modus: [B]arcode oder [I]Ds\n";

my $date = localtime->strftime('%Y%m%d');

mkdir "log_$date";

unless ($mode eq 'B' || $mode eq 'I') {
    die "Modus falsch angegeben, muss entweder [B]arcode oder [I]Ds sein\n";
}

my $base_url = "https://api-eu.hosted.exlibrisgroup.com/almaws/v1/";

open(my $key_data, '<:encoding(utf8)', $key_file) or die "Could not open '$key_file' $!\n";
my $api_key = <$key_data>;
close $key_data;

my $csv = Text::CSV->new ({
    binary    => 1,
    auto_diag => 1,
    sep_char  => ';'    
});

my $log = Text::CSV->new ({
    binary    => 1,
    auto_diag => 1,
    sep_char  => ';'    
});

 
open(my $log_data, '>:encoding(utf8)', $log_file) or die "Could not open '$log_file' $!\n";

my(@log_heading) = ("MMS ID", "HOL ID", "Item ID", "Barcode", "Item call num old", "Item call num new", "XML old", "XML new");
$log->print($log_data, \@log_heading);    # Array ref!

open(my $csv_data, '<:encoding(utf8)', $csv_file) or die "Could not open '$csv_file' $!\n";

while (my $csv_line = $csv->getline( $csv_data )) {
  
    my $ua = LWP::UserAgent->new();
    my $xml_parser = XML::LibXML->new; 

    my $mms_id;
    my $hol_id;
    my $item_id;
    my $barcode;
    my $call_no_old;
    my $call_no_new;

    my $url_get;

    if ($mode eq 'B') {
        $barcode     = $csv_line->[0];
        $call_no_new = $csv_line->[1];

        $url_get = $base_url . "items?item_barcode=$barcode&apikey=$api_key";

    } else {
        $mms_id      = $csv_line->[0];
        $hol_id      = $csv_line->[1];
        $item_id     = $csv_line->[2];
        $call_no_new = $csv_line->[3];
        
        $url_get = $base_url . "bibs/$mms_id/holdings/$hol_id/items/$item_id?apikey=$api_key";
    }
 
    my $get = HTTP::Request->new(GET=>$url_get);
    my $xml_ref = $ua->request($get); 

    my $xml = $xml_parser->parse_string($$xml_ref{'_content'});
    my $xml_old = $xml->toString;

    $mms_id      = $xml->findvalue('//mms_id'); 
    $hol_id      = $xml->findvalue('//holding_id'); 
    $item_id     = $xml->findvalue('//pid'); 
    $barcode     = $xml->findvalue('//barcode'); 
    $call_no_old = $xml->findvalue('//alternative_call_number'); 

    unless ($mms_id && $hol_id && $item_id ) {
        print "Item does not exist: $csv_line->[0] $csv_line->[1] $csv_line->[2] $csv_line->[3] \n"; 
        next;
    }
    
    my ($item_call_number) = $xml->findnodes('//alternative_call_number'); 

    ### Fehlermeldung wenn Keine Daten vorhanden sind!!

    $item_call_number->removeChildNodes();
    $item_call_number->appendText($call_no_new);
    

    my $xml_new = $xml->toString;
    
    #my $save_file = "test.save";
    my $save_file = "./log_$date/$barcode.sav";
    open(my $save_data, '>:encoding(utf8)', $save_file) or die "Could not open '$save_file' $!\n";
    print $save_data $xml_old;
    
    #print $mms_id . " " .  $hol_id . " " . $item_id . " " . $call_no_old . " " .  $call_no_new .  "\n";

    my(@log_line) = ($mms_id, $hol_id, $item_id, $barcode, $call_no_old, $call_no_new, $xml_old, $xml_new);
    $log->print($log_data, \@log_line);    # Array ref!

    close $save_data;
}

if (not $csv->eof) {
    $csv->error_diag();
}

close $csv_data;     
close $log_data;
     
exit;
