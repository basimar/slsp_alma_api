#!/usr/bin/perl
use strict;
use warnings;

use Data::Dumper;
use LWP;
use Time::Piece;
use Text::CSV;
use XML::LibXML;

# Argumente einlesen
my $csv_file = $ARGV[0] or die "1. Argument: CSV-File mit Input\n";
my $log_file = $ARGV[1] or die "2. Argument: CSV-File mit Output\n";
my $key_file = $ARGV[2] or die "3. Argument: Textfile mit API_KEY\n";
my $mode = $ARGV[3] or die "4. Argument: Inputfile-Modus: [B]arcode oder [I]Ds\n";

# Modus muss entweder B (Inputfile enthält Barcodes) oder I (Inputfile enthält MMS, Holding und Item-ID) sein
unless ($mode eq 'B' || $mode eq 'I') {
    die "Modus falsch angegeben, muss entweder [B]arcode oder [I]Ds sein\n";
}

# Aktuelles Datum auslesen und Ordner für Logfiles erstellen
my $date = localtime->strftime('%Y%m%d');
mkdir "log_$date";


# Datei mit API-Key öffnen und Key in Variable abspeichern
open(my $key_fh, '<:encoding(utf8)', $key_file) or die "Could not open '$key_file' $!\n";
my $api_key = <$key_fh>;
close $key_fh;

# Base-URL für Alma REST-API definieren (für alle IZs identisch)
my $base_url = "https://api-eu.hosted.exlibrisgroup.com/almaws/v1/";

# Datei für Logfile öffnen
open(my $log_fh, '>:encoding(utf8)', $log_file) or die "Could not open '$log_file' $!\n";

# CSV-Objekt für Logfile initialisieren
my $log = Text::CSV->new ({
    binary    => 1,
    auto_diag => 1,
    sep_char  => ';'    
});

# Header für CSV-Logfile ausgeben
my(@log_heading) = ("MMS ID", "HOL ID", "Item ID", "Barcode", "Item call num old", "Item call num new");
$log->print($log_fh, \@log_heading);    # Array ref!

# CSV-Objekt für Inputfile initialisieren
my $csv = Text::CSV->new ({
    binary    => 1,
    auto_diag => 1,
    sep_char  => ';'    
});

# Inputfile öffnen und jede Zeile bearbeiten
open(my $csv_fh, '<:encoding(utf8)', $csv_file) or die "Could not open '$csv_file' $!\n";

while (my $csv_line = $csv->getline( $csv_fh )) {

    # Variablen für Exemplarinformationen deklarireren  
    my $mms_id;
    my $hol_id;
    my $item_id;
    my $barcode;
    my $call_no_old;
    my $call_no_new;

    # Definition der URL um die Exemplarinformationen per API auszulesen
    my $url_get;

    # Je nach Typ der Inputdatei müssen anderen Spalten der csv-Inputdatei ausgelesen und der API-Request anders zusammengestellt werden
    if ($mode eq 'B') {
 
        # Auslesen der Spalten in der Input-Datei
        $barcode     = $csv_line->[0];
        $call_no_new = $csv_line->[1];
    
        # Prüfung, ob die Zeile wirklich Daten enthält. Nur dann wird der API-Request generiert, sonst bricht die Verarbeitung der Zeile ab
        if ( $barcode && $call_no_new ) {
            $url_get = $base_url . "items?item_barcode=$barcode&apikey=$api_key";
        } else {
            print "Empty line\n";
            next;
        }

    } else {
        
        # Auslesen der Spalten in der Input-Datei
        $mms_id      = $csv_line->[0];
        $hol_id      = $csv_line->[1];
        $item_id     = $csv_line->[2];
        $call_no_new = $csv_line->[3];
        
        # Prüfung, ob die Zeile wirklich Daten enthält. Nur dann wird der API-Request generiert, sonst bricht die Verarbeitung der Zeile ab
        if ( $mms_id && $hol_id && $item_id && $call_no_new ) {
            $url_get = $base_url . "bibs/$mms_id/holdings/$hol_id/items/$item_id?apikey=$api_key";
        } else {
            print "Empty line\n";
            next;
        }
    }
 
    # Ausgabe des API-Request um Exemplar auszulesen 
    print "Read out item: " . $url_get;
   
    # API-Request wird mit den Modulen LWP::UserAgent und HTTP::Request abgesetzt. Mit "GET" werden die Exemplarinformationen ausgelesen
    my $ua_get = LWP::UserAgent->new();
    my $get = HTTP::Request->new('GET',$url_get);

    # Der API-Request liefert die Exemplardaten als XML. Diese werden mit XML::LibXML als XML-Objekt ausgegeben    
    my $xml_parser = XML::LibXML->new; 
    my $xml_ref = $ua_get->request($get); 
    my $xml = $xml_parser->parse_string($$xml_ref{'_content'});

    # Das XML-Objekt mit den ursprünglichen Exemplardaten wird als String abgespeichert 
    my $xml_old = $xml->toString;

    # Auslesen der Exemplardaten aus dem XML-Objekt
    $mms_id      = $xml->findvalue('//mms_id'); 
    $hol_id      = $xml->findvalue('//holding_id'); 
    $item_id     = $xml->findvalue('//pid'); 
    $barcode     = $xml->findvalue('//barcode'); 
    $call_no_old = $xml->findvalue('//alternative_call_number'); 

    # Falls die Felder MMS ID, Holding ID und Item ID nicht im XML-Objekt vorhanden sind, war der API Request nicht erfolgreich. In diesem Fall wird eine Fehlermeldung ausgegeben und die Verarbeitung der Zeile wird abgebrochen
    unless ($mms_id && $hol_id && $item_id ) {
        print "Item does not exist: $csv_line->[0] $csv_line->[1] $csv_line->[2] $csv_line->[3] \n"; 
        next;
    }
   
    # Die zu ändernen Exemplarfelder (Item call number und Item Call number type) werden als eigene Objekte abgespeichert 
    my ($item_call_number) = $xml->findnodes('//alternative_call_number'); 
    my ($item_call_number_type) = $xml->findnodes('//alternative_call_number_type'); 

    # Hier werden im XML-Tag für die Item call number zuerst alle Child Nodes entfernt und dann die neue Signatur aus der csv-Datei eingespielt
    $item_call_number->removeChildNodes();
    $item_call_number->appendText($call_no_new);
    
    # Hier werden im XML-Tag für den Item call number type zuerst alle Child Nodes entfernt und dann neu der Wert "4" vergeben 
    $item_call_number_type->removeChildNodes();
    $item_call_number_type->appendText('4');
   
    # Das XML-Objekt mit den angepasssten Exemplardaten wird als String abgespeichert 
    my $xml_new = $xml->toString;

    # Der API-Request zum Ändern der Exemplardaten wird mit den Modulen LWP::UserAgent und HTTP::Request abgesetzt. Mit "PUT" werden die Exemplarinformationen angepasst.
    # Zusätzlich müssen hier der Header ($header_put) und die Exemplardaten ($xml_new) mitgegeben werden
    my $header_put = ['Content-Type' => 'application/xml; charset=UTF-8'];
    my $url_put = $base_url . "bibs/$mms_id/holdings/$hol_id/items/$item_id?apikey=$api_key";
    my $put = HTTP::Request->new('PUT',$url_put, $header_put, $xml_new);
    my $ua_put = LWP::UserAgent->new();
    
    # Hier wird der PUT-Request abgesetzt, die Antwort von Alma wird ausgegeben
    print Dumper($ua_put->request($put)); 
   
    # Die unveränderten Exemplardaten werden pro Exemplar in einer eigenen Datei im Ordner log_$date abgespeichert 
    my $save_file = "./log_$date/$barcode.sav";
    open(my $save_data, '>:encoding(utf8)', $save_file) or die "Could not open '$save_file' $!\n";
    print $save_data $xml_old;
    close $save_data;
   
    # Das csv-Logfile wird mit den Daten des geänderten Exemplars ergänzt 
    my(@log_line) = ($mms_id, $hol_id, $item_id, $barcode, $call_no_old, $call_no_new );
    $log->print($log_fh, \@log_line);    # Array ref!
}

# Prüfung ob die Input-Datei korrekt verarbeitet wurde
if (not $csv->eof) {
    $csv->error_diag();
}

close $csv_fh;     
close $log_fh;
     
exit;
