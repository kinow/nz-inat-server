#! /bin/bash

# gets Aus iNat DCA & load into PG
# exemplar by Brent Wood, March 2016 
# does not tidy up logfiles using logrotate - tbd at some stage

SRC="http://www.inaturalist.org/observations/ala-observations-dwca.zip"
WGET_LOG="./wget_nw.log"
DCA=nw_obs.zip
LOG=nw.log
DB=inat

# get rid of any existing archive & files
rm -f $DCA metadata.eml.xml meta.xml observations.csv images.csv 

# download the specified file
wget -q -a $WGET_LOG -O $DCA $SRC

if [ ! -r $DCA ] ; then
  date >> $LOG
  echo "No download found" >> $LOG
  exit
fi


# create temporary table for new data
# create database if it doesn't exist
FLAG=`psql -l | grep $DB`
if [ "$FLAG" = "" ] ; then
  # no such database
  createdb $DB
  psql -q -d $DB -c "create extension postgis;"
fi

# create temporary table
export PGOPTIONS='--client-min-messages=warning'
psql -d $DB -qc "drop table if exists load_data;"
psql -d $DB -qc "create table load_data
                (id                   bigint primary key,
                 occurrence_id        varchar(100),
                 basis_of_record      varchar(50),
                 modified             timestamp,
                 institution_code     varchar(15),
                 collection_code      varchar(15),
                 dataset_name         varchar(120),
                 information_withheld varchar(125),
                 catalog_number       varchar(120),
                 references_          varchar(120),
                 occurrence_remarks   text,
                 occurrence_details   text,
                 recorded_by          varchar(40),
                 establishment_means  varchar(15),
                 event_date           varchar(50),
                 event_time           varchar(50),
                 verbatim_event_date  varchar(50),
                 verbatim_locality    varchar(150),
                 decimal_latitude     decimal(7,5),
                 decimal_longitude    decimal(8,5),
                 coordinate_uncertaint_in_meters integer,  
                 country_code         char(2),
                 identification_id    integer,
                 date_identified      timestamp,
                 identification_remarks text,
                 taxon_id             integer,
                 scientific_name      varchar(100),
                 taxon_rank           varchar(25),
                 kingdom              varchar(25),
                 phylum               varchar(25),
                 class                varchar(25),
                 order_               varchar(25),
                 family               varchar(25),
                 genus                varchar(25),
                 license              varchar(125),
                 rights               varchar(125),
                 rights_holder        varchar(125));"


# unzip downloaded DCA file
unzip -qq $DCA

# sort out fields with commas using awk csvutils
#  http://lorance.freeshell.org/csvutils/

bash ./csvutils/csv2csv -S "|" -l "-1" observations.csv | sed 's/|$//' > obs2.csv

# load data into temporary table (stripping header with tail)
cat obs2.csv | \
  tail -n +2 | \
  psql -d $DB -qc "copy load_data from STDIN with delimiter '|' null '';"

# create postgis geometry from lat/long values
psql -d $DB -qc "alter table load_data add column geom geometry(POINT,4326);"
psql -d $DB -qc "update load_data 
                set geom=ST_SetSRID(ST_MakePoint(decimal_longitude, decimal_latitude),4326);"


# drop working table, & replace it with the new one
# this provides a near-zero downtime for a dataset update 
psql -d $DB -qc "drop table if exists nw_obs;"
psql -d $DB -qc "alter table load_data rename to nw_obs;"