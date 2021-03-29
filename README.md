# slsp_alma_api

Set of scripts for changing data in Alma via API

Requirements:

The Perl scripts were tested both with Perl v5.28.1 and v5.22.1. They require the following modules:

use Data::Dumper;
use LWP;
use Time::Piece;
use Text::CSV;
use XML::LibXML;

The last two modules can be installed on a Debian/Ubuntu with the following commands:

sudo apt-get install libtext-csv-perl
sudo apt-get install libxml-libxml-perl

List of scripts:

change_item_call_no.pl: Script for changing the item call number in Alma based on a csv list
change_holding_call_no.pl: Script for changing the holding call number in Alma based on a csv list
change_bibliographic.pl: Script with examples how to change bibliographic records in Alma based on a csv list
