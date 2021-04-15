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
my(@log_heading) = ("MMS ID", "Field old", "Field new");
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

    # Variablen für bibliographischen Felder deklarieren und aus Input-Datei auslesen
    my $mms_id      = $csv_line->[0];
    my $field_new   = $csv_line->[1];
    my $field_old;

    my $url_get;

    # Prüfung, ob die Zeile wirklich Daten enthält. Nur dann wird der API-Request generiert, sonst bricht die Verarbeitung der Zeile ab
    if ( $mms_id && $field_new ) {
        $url_get = $base_url . "bibs/$mms_id?apikey=$api_key";
    } else {
        print "Empty line\n";
        next;
    }
 
    # Ausgabe des API-Request um bibliographische Aufnahme auszulesen 
    print "Read out item: " . $url_get;
   
    # API-Request wird mit den Modulen LWP::UserAgent und HTTP::Request abgesetzt. Mit "GET" wird die bibliographische Aufnahme ausgelesen
    my $ua_get = LWP::UserAgent->new();
    my $get = HTTP::Request->new('GET',$url_get);

    # Der API-Request liefert die Bibdaten als MARCXML. Diese werden mit XML::LibXML als XML-Objekt ausgegeben    
    my $xml_parser = XML::LibXML->new; 
    my $xml_ref = $ua_get->request($get); 
    my $xml = $xml_parser->parse_string($$xml_ref{'_content'});

    # Das XML-Objekt mit den ursprünglichen bibliographischen Informationen wird als MARCXML wird als String abgespeichert 
    my $xml_old = $xml->toString;

    # Auslesen der MARC-Daten aus dem XML-Objekt
    $mms_id = $xml->findvalue('/bib/mms_id');
     
    # Beispiele um Felder mit xpath auszulesen 
   
    # Leader auslesen 
    # my $leader = $xml->findvalue('/bib/record/leader');
    
    # Feld 008 auslesen
    # my $field_008  = $xml->findvalue('/bib/record/controlfield[@tag="008"]');
    
    # Feld 245 auslesen
    # my $field_245  = $xml->findvalue('/bib/record/datafield[@tag="245"]');
    
    # Feld 245a auslesen
    # my $field_245a  = $xml->findvalue('/bib/record/datafield[@tag="245"]/subfield[@code="a"]');
    
    # Feld 245ab auslesen
    # my $field_245ab  = $xml->findvalue('/bib/record/datafield[@tag="245"]/subfield[@code="a" or @code="b"]');
    
    # Feld 246 auslesen (inkl. Auswertung Indikatoren) 
    # my $field_246  = $xml->findvalue('/bib/record/datafield[@tag="246" and @ind1="1" and @ind2="3"]');
    
    # Felder 650 auslesen - gibt alle Felder zurück 
    # my $fields_650 = $xml->findvalue('/bib/record/datafield[@tag="650"]');
    
    # Felder 650 auslesen - erstes Feld 
    # my $field_650 = $xml->findvalue('/bib/record/datafield[@tag="650"][1]');
    
    # Felder 650 auslesen - alle Felder mit Unterfeld $2 gnd 
    # my $field_650 = $xml->findvalue('/bib/record/datafield[@tag="650" and subfield[@code="2"]="gnd"]');
    
    # Felder 650a auslesen -  mit Unterfeld $2 ethudk 
    # my $field_650a = $xml->findvalue('/bib/record/datafield[@tag="650" and subfield[@code="2"]="ethudk"]/subfield[@code="a"]');
    
    # Falls das Feld MMS ID nicht im XML-Objekt vorhanden sind, war der API Request nicht erfolgreich. In diesem Fall wird eine Fehlermeldung ausgegeben und die Verarbeitung der Zeile wird abgebrochen
    unless ($mms_id ) {
        print "BIB does not exist: $csv_line->[0] $csv_line->[1] \n"; 
        next;
    }

    # Das zu ändernde MARC-Feld  wird als eigenes Objekte abgespeichert 
    # my ($field) = $xml->findnodes(''); 

    # Hier wird im XML-Tag für Feld xxx zuerst alle Child Nodes entfernt und dann die neue Signatur aus der csv-Datei eingespielt
    # $field->removeChildNodes();
    # $field->appendText($field_new);
    
    # Das XML-Objekt mit den angepasssten bibliographischen Daten wird als String abgespeichert 
    my $xml_new = $xml->toString;

    # Der API-Request zum Ändern der bibliographischen Aufnahme  wird mit den Modulen LWP::UserAgent und HTTP::Request abgesetzt. Mit "PUT" werden die MARC-Daten angepasst.
    # Zusätzlich müssen hier der Header ($header_put) und die MARC-Daten ($xml_new) mitgegeben werden
    my $header_put = ['Content-Type' => 'application/xml; charset=UTF-8'];
    my $url_put = $base_url . "bibs/$mms_id?apikey=$api_key";
    my $put = HTTP::Request->new('PUT',$url_put, $header_put, $xml_new);
    my $ua_put = LWP::UserAgent->new();
    
    # Hier wird der PUT-Request abgesetzt, die Antwort von Alma wird ausgegeben
    # Auskommentieren für Testrun
    # $ua_put->request($put); 

    # Variante in der die API-Antwort ausgegeben wird
    # print Dumper($ua_put->request($put)); 
   
    # Die unveränderten bibliographischen Daten werden pro Aufnahme in einer eigenen Datei im Ordner log_$date abgespeichert 
    my $save_file = "./log_$date/$mms_id.sav";
    open(my $save_data, '>:encoding(utf8)', $save_file) or die "Could not open '$save_file' $!\n";
    print $save_data $xml_old;
    close $save_data;
   
    # Das csv-Logfile wird mit den Daten der geänderten Aufnahme ergänzt 
    my(@log_line) = ($mms_id, $field_old, $field_new );
    $log->say($log_fh, \@log_line);    # Array ref!
}

# Prüfung ob die Input-Datei korrekt verarbeitet wurde
if (not $csv->eof) {
    $csv->error_diag();
}

close $csv_fh;     
close $log_fh;
     
exit;
