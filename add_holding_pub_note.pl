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

# Aktuelles Datum auslesen und Ordner für Logfiles erstellen
my $date = localtime->strftime('%Y%m%d');
mkdir "log_$date";

# Datei mit API-Key öffnen und Key in Variable abspeichern
open(my $key_fh, '<:encoding(utf8)', $key_file) or die "Could not open '$key_file' $!\n";
my $api_key = <$key_fh>;
chomp $api_key;
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
my(@log_heading) = ("MMS ID", "HOL ID", "HOL pub notes old", "HOL pub notes new");
$log->say($log_fh, \@log_heading);    # Array ref!

# CSV-Objekt für Inputfile initialisieren
my $csv = Text::CSV->new ({
    binary    => 1,
    auto_diag => 1,
    sep_char  => ';'    
});

# Inputfile öffnen und jede Zeile bearbeiten
open(my $csv_fh, '<:encoding(utf8)', $csv_file) or die "Could not open '$csv_file' $!\n";

while (my $csv_line = $csv->getline( $csv_fh )) {

    # Variablen für Holdinginformationen deklarieren und aus Input-Datei auslesen
    my $mms_id       = $csv_line->[0];
    my $hol_id       = $csv_line->[1];
    my $pub_note_new = $csv_line->[2];

    my $url_get;

    # Prüfung, ob die Zeile wirklich Daten enthält. Nur dann wird der API-Request generiert, sonst bricht die Verarbeitung der Zeile ab
    if ( $mms_id && $hol_id && $pub_note_new ) {
        $url_get = $base_url . "bibs/$mms_id/holdings/$hol_id?apikey=$api_key";
    } else {
        print "Empty line\n";
        next;
    }
 
    # Ausgabe des API-Request um Holding auszulesen 
    print "Read out item: " . $url_get;
   
    # API-Request wird mit den Modulen LWP::UserAgent und HTTP::Request abgesetzt. Mit "GET" werden die Holdinginformationen ausgelesen
    my $ua_get = LWP::UserAgent->new();
    my $get = HTTP::Request->new('GET',$url_get);

    # Der API-Request liefert die Holdingdaten als MARCXML. Diese werden mit XML::LibXML als XML-Objekt ausgegeben    
    my $xml_parser = XML::LibXML->new; 
    my $xml_ref = $ua_get->request($get); 
    my $xml = $xml_parser->parse_string($$xml_ref{'_content'});

    # Das XML-Objekt mit den ursprünglichen Holdinginformationen als MARCXML wird als String abgespeichert 
    my $xml_old = $xml->toString;

    # Auslesen der Holding-Daten aus dem XML-Objekt
    $hol_id      = $xml->findvalue('/holding/holding_id'); 
    my $hol_field_852_old = $xml->findvalue('/holding/record/datafield[@tag="852" and @ind1="4"]'); 

    # Falls die Felder MMS ID und Holding ID nicht im XML-Objekt vorhanden sind, war der API Request nicht erfolgreich. In diesem Fall wird eine Fehlermeldung ausgegeben und die Verarbeitung der Zeile wird abgebrochen
    unless ($mms_id && $hol_id ) {
        print "Holding does not exist: $csv_line->[0] $csv_line->[1] $csv_line->[2] \n"; 
        next;
    }

    # Das zu ergänzende MARC-Feld (8524) wird als eigenes Objekte abgespeichert 
    my ($hol_field_852) = $xml->findnodes('/holding/record/datafield[@tag="852" and @ind1="4"]'); 

    # Hier wird im XML-Tag für Feld 8524 ein neues Unterfeld $z mit der neuen Public Note aus der csv-Datei eingespielt (existierendes Unterfeld $z bleibt erhalten).
    
    my $new_subfield_z= $xml->createElement("subfield");
    $new_subfield_z->setAttribute( "code", "z");
    $new_subfield_z->appendText( $pub_note_new);
    $hol_field_852->appendChild($new_subfield_z);
    
    # Das XML-Objekt mit den angepasssten Holdingdaten wird als String abgespeichert 
    my $xml_new = $xml->toString;

    print $xml_new . "\n";
    
    # Das neue Feld 852 wird für das Logfile ausgelesen 
    my $hol_field_852_new = $xml->findvalue('/holding/record/datafield[@tag="852" and @ind1="4"]'); 

    # Der API-Request zum Ändern der Holdingdaten wird mit den Modulen LWP::UserAgent und HTTP::Request abgesetzt. Mit "PUT" werden die Holdingdaten angepasst.
    # Zusätzlich müssen hier der Header ($header_put) und die Holdingdaten ($xml_new) mitgegeben werden
    my $header_put = ['Content-Type' => 'application/xml; charset=UTF-8'];
    my $url_put = $base_url . "bibs/$mms_id/holdings/$hol_id?apikey=$api_key";
    my $put = HTTP::Request->new('PUT',$url_put, $header_put, $xml_new);
    my $ua_put = LWP::UserAgent->new();
    
    # Hier wird der PUT-Request abgesetzt, die Antwort von Alma wird ausgegeben
    # Auskommentieren für Testrun
    # $ua_put->request($put); 

    # Variante in der die API-Antwort ausgegeben wird
    print Dumper($ua_put->request($put)); 
   
    # Die unveränderten Holdingdaten werden pro Holding in einer eigenen Datei im Ordner log_$date abgespeichert 
    my $save_file = "./log_$date/$hol_id.sav";
    open(my $save_data, '>:encoding(utf8)', $save_file) or die "Could not open '$save_file' $!\n";
    print $save_data $xml_old;
    close $save_data;
   
    # Das csv-Logfile wird mit den Daten des geänderten Holdings ergänzt 
    my(@log_line) = ($mms_id, $hol_id, $hol_field_852_old, $hol_field_852_new );
    $log->say($log_fh, \@log_line);    # Array ref!
}

# Prüfung ob die Input-Datei korrekt verarbeitet wurde
if (not $csv->eof) {
    $csv->error_diag();
}

close $csv_fh;     
close $log_fh;
     
exit;
