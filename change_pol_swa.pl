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
my(@log_heading) = ("POL ID", "POL old", "POL new");
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

    # Variablen für POL Informationen deklarieren und aus Input-Datei auslesen
    my $pol_id      = $csv_line->[0];

    my $url_get;

    # Prüfung, ob die Zeile wirklich Daten enthält. Nur dann wird der API-Request generiert, sonst bricht die Verarbeitung der Zeile ab
    if ( $pol_id ) {
        $url_get = $base_url . "acq/po-lines/$pol_id?apikey=$api_key";
    } else {
        print "Empty line\n";
        next;
    }
 
    # Ausgabe des API-Request um POL auszulesen 
    print "Read out POL " . $url_get;
   
    # API-Request wird mit den Modulen LWP::UserAgent und HTTP::Request abgesetzt. Mit "GET" werden die Holdinginformationen ausgelesen
    my $ua_get = LWP::UserAgent->new();
    my $get = HTTP::Request->new('GET',$url_get);

    # Der API-Request liefert die Holdingdaten als MARCXML. Diese werden mit XML::LibXML als XML-Objekt ausgegeben    
    my $xml_parser = XML::LibXML->new; 
    my $xml_ref = $ua_get->request($get); 
    my $xml = $xml_parser->parse_string($$xml_ref{'_content'});

    # Das XML-Objekt mit den ursprünglichen Holdinginformationen als MARCXML wird als String abgespeichert 
    my $xml_old = $xml->toString;

    print $xml_old . "\n";

    $pol_id      = $xml->findvalue('/po_line/number'); 

    # Falls das Feld POL number nicht im XML-Objekt vorhanden ist, war der API Request nicht erfolgreich. In diesem Fall wird eine Fehlermeldung ausgegeben und die Verarbeitung der Zeile wird abgebrochen
    unless ($pol_id ) {
        print "POL does not exist: $csv_line->[0] \n"; 
        next;
    }

    # Die zu ändernden POL-Felder (POL type & POL number & PO number) werden als eigene Objekte abgespeichert 
    my ($pol_type) = $xml->findnodes('/po_line/type'); 
    my ($pol_number) = $xml->findnodes('/po_line/number'); 
    my ($po_number) = $xml->findnodes('/po_line/po_number'); 

    # Hier werden im Feld POL type zuerst alle Child Nodes entfernt und dann der neue POL type eingespielt 
    $pol_type->removeChildNodes();
    $pol_type->appendText("PRINTED_JOURNAL_CO");
    
    # Hier werden im Feld POL number alle Child Nodes entfernt 
    $pol_number->removeChildNodes();
    
    # Hier werden im Feld PO number alle Child Nodes entfernt 
    $po_number->removeChildNodes();
    
    # Das XML-Objekt mit den angepasssten Holdingdaten wird als String abgespeichert 
    my $xml_new = $xml->toString;

    # Der API-Request zum Ändern der Holdingdaten wird mit den Modulen LWP::UserAgent und HTTP::Request abgesetzt. Mit "PUT" werden die Holdingdaten angepasst.
    # Zusätzlich müssen hier der Header ($header_put) und die Holdingdaten ($xml_new) mitgegeben werden
    #
    # Um POL per API anzulegen muss immer der Parameter profile_code mitgegeben werden (enthält Code des New Order integration profiles)
    
    my $header_post = ['Content-Type' => 'application/xml; charset=UTF-8'];
    my $url_post = $base_url . "acq/po-lines?apikey=$api_key&profile_code=SLSP-UBS-ORDER-API-INTOTA";
    my $post = HTTP::Request->new('POST',$url_post, $header_post, $xml_new);
    my $ua_post = LWP::UserAgent->new();
    
    # Hier wird der POST-Request abgesetzt, die Antwort von Alma wird ausgegeben
    # Auskommentieren für Testrun
    #$ua_post->request($post); 

    # Variante in der die API-Antwort ausgegeben wird
    print Dumper($ua_post->request($post)); 
   
    # Die unveränderten POL-Daten und die neu anzulegendeni POL  werden pro POL in einer eigenen Datei im Ordner log_$date abgespeichert 
    my $save_file = "./log_$date/$pol_id.sav";
    my $new_file = "./log_$date/$pol_id.new";
    open(my $save_data, '>:encoding(utf8)', $save_file) or die "Could not open '$save_file' $!\n";
    open(my $new_data, '>:encoding(utf8)', $new_file) or die "Could not open '$new_file' $!\n";
    print $save_data $xml_old;
    print $new_data $xml_new;
    close $save_data;
    close $new_data;
   
    # Das csv-Logfile wird mit den Daten der geänderten POL ergänzt 
    my(@log_line) = ($pol_id, $xml_old, $xml_new );
    $log->say($log_fh, \@log_line);    # Array ref!
}

# Prüfung ob die Input-Datei korrekt verarbeitet wurde
if (not $csv->eof) {
    $csv->error_diag();
}

close $csv_fh;     
close $log_fh;
     
exit;
