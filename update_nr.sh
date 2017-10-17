#!/bin/bash

# parse parameters

if [[ $# -lt 6 ]]; then
    echo "Please provide 3 arguments: -d /path/to/data/dir"\
", -l path/to/loc_file"\
" and -n 0 (don't download) or 1 (download)."
    exit 1
fi

while getopts "d:n:l:" opt; do
    case $opt in 
        d)
            db_path=$OPTARG
            if [ ! -d $db_path ]; then
                echo "The directory $db_path was not found. Please provide a valid data directory"
                exit 1
            fi
        ;;
        n)
            download_nr=$OPTARG
            if [ $download_nr != 0 -a $download_nr != 1 ]; then
                echo "invalid value for -n, must be 0 or 1"
                exit 1
            fi
        ;;
        l)
            loc_path=$OPTARG
            if [ ! -e $loc_file ]; then
                echo "specified loc file does not exist"
                exit 1
            fi
        ;;
        \?)
            echo "Invalid option: -$OPTARG"
            exit 1
        ;;
        :)
            echo "Option -$OPTARG requires an argument."
            exit 1
        ;;
    esac
done

export PATH=$PATH:/opt/galaxy/tool_dependencies/blast/2.5.0/iuc/package_blast_plus_2_5_0/5dd2b68c7d04

#============================================================#
# Step 1: Download NR (optional) and extract human and mouse # 
#============================================================#

# for downloading, go to nr dir
cd $db_path/nr 

## # get single timestamp, before download starts
dateMostRecentDownload=$(date +'%m_%d_%Y')
 
# write for later retrieval-- append to end of list
mostRecentDatesPath=/opt/galaxy/galaxy-app/cron/mostRecentDates.txt
echo $dateMostRecentDownload >> $mostRecentDatesPath

echo "Updating nr database on $dateMostRecentDownload"

# run update script
# depends on whether 'download_nr' is 0 (no) or 1 (yes)

if [ $download_nr -eq 1 ]; then
    update_blastdb.pl -passive 1 --decompress 1
    echo "database updated"
else 
    echo "skipping download"
fi

# make directory for most recent extractions 
mkdir $db_path/$dateMostRecentDownload

echo "extracting full nr database for diamondizing..."
blastdbcmd -db nr -entry all \
    -out $db_path/$dateMostRecentDownload/nr.fasta

if [ $? -eq 0 ]; then
    echo "full nr extracted"
else
    echo "full nr extraction failed. exiting"
    exit 1
fi

echo "extracting human sequences..."
#extract and build human nr database
blastdbcmd -db nr -entry all -outfmt "%g %T" | \
    awk ' { if ($2 == 9606) { print $1 } } ' | \
    blastdbcmd -db nr -target_only -entry_batch - \
        -out $db_path/$dateMostRecentDownload/human_nr_$dateMostRecentDownload.fasta

if [ $? -eq 0 ]; then
    echo "human sequences extracted"
else
    echo "human extraction failed. exiting"
    exit 1
fi

echo "building human database..."

makeblastdb \
    -in $db_path/$dateMostRecentDownload/human_nr_$dateMostRecentDownload.fasta \
    -out $db_path/$dateMostRecentDownload/human_nr_db_$dateMostRecentDownload \
    -dbtype prot &&\
    rm $db_path/$dateMostRecentDownload/human_nr_$dateMostRecentDownload.fasta
    # if makeblastdb succeeds, remove human fasta to save space

if [ $? -eq 0 ]; then
    echo "human database built"
else
    echo "human database build failed. exiting"
    exit 1
fi

echo "extracting mouse sequences..."
#extract and build mouse_nr database
blastdbcmd -db nr -entry all -outfmt "%g %T" | \
    awk ' { if ($2 == 10090) { print $1 } } ' | \
    blastdbcmd -db nr -target_only -entry_batch - \
        -out $db_path/$dateMostRecentDownload/mouse_nr_$dateMostRecentDownload.fasta

if [ $? -eq 0 ]; then
    echo "mouse sequences extracted"
else 
    echo "mouse extraction failed. exiting"
    exit 1
fi

echo "building mouse database..."
makeblastdb \
    -in $db_path/$dateMostRecentDownload/mouse_nr_$dateMostRecentDownload.fasta \
    -out $db_path/$dateMostRecentDownload/mouse_nr_db_$dateMostRecentDownload \
    -dbtype prot &&\
    rm $db_path/$dateMostRecentDownload/mouse_nr_$dateMostRecentDownload.fasta

if [ $? -eq 0 ]; then
    echo "mouse database built"
else 
    echo "mouse database build failed. exiting"
    exit 1
fi

echo "taking snapshot of whole nr"
# finally, copy whole nr database to most recent download folder
cp nr.* $db_path/$dateMostRecentDownload

if [ $? -eq 0 ]; then
    echo "whole nr copied to $db_path/$dateMostRecentDownload"
else
    echo "whole nr copy failed. exiting"
    exit 1
fi

# rename with date
echo "renaming nr files in $db_path/$dateMostRecentDownload"
for f in $db_path/$dateMostRecentDownload/nr.*; do mv "$f" "${f/nr/nr_$dateMostRecentDownload}"; done

if [ $? -eq 0 ]; then
    echo "nr files renamed"
else
    echo "rename failed. exiting"
    exit 1
fi

# update index in alias file
echo "updating index in alias file."
sed -i "s/nr/nr_$dateMostRecentDownload/g" $db_path/$dateMostRecentDownload/nr_$dateMostRecentDownload.pal

if [ $? -eq 0 ]; then
    echo "index in alias file updated"
else
    echo "updating index failed. exiting"
    exit 1
fi

if [ $? -ne 0 ]; then
    echo "Database download and extraction failed. Exiting."
    exit 1
fi

#=========================================#
#     Step 2: Update the .loc file        #
#=========================================#
# top line is always "nr_current" and represents the most recent DB
## presumed blastdb_p layout, number refers to months ago - actual file has dates

#1  nr    nr_current    /path_to_nr_date
#2  nr_human_date    nr_human_current    /path_to_nr_human_0
#3  nr_mouse_date    nr_mouse_current    /path_to_nr_mouse_0
#4  nr_0             ..etc...             ...etc...
#5  nr_human_0
#6  nr_mouse_0
#7  nr_3
#8  nr_human_3
#9  nr_mouse_3
#10 nr_6
#11 nr_human_6
#12 nr_mouse_6
#13 nr_9
#14 nr_human_9
#15 nr_mouse_9

h_id=human_nr_db_$dateMostRecentDownload
m_id=mouse_nr_db_$dateMostRecentDownload
nr_id=nr_$dateMostRecentDownload

# the only db path we're working with is dir with most recent
most_recent_path=$db_path/$dateMostRecentDownload

#formats entry correctly (unique_id <tab> listing_name <tab> database_path
h_line=$h_id"\t"$h_id"\t"$db_path/$h_id
m_line=$m_id"\t"$m_id"\t"$db_path/$m_id
nr_line=nr_$dateMostRecentDownload"\t"nr_$dateMostRecentDownload"\t"$most_recent_path/$nr_id

#correctly formats the entries in the blastdb_p.loc file

# when setting up automatic database updating, first clean blastdb_p.loc file
# remove any lines that start with #
sed -i 's/^#.*$//g' $loc_path


# count number of lines in current loc file
nLines=$(wc -l $loc_path | awk '{print $1 }')

# if the number of lines is 0, insert first three lines instead of replacing them
if [ $nLines -lt 3 ]; then
    # Ni inserts before the Nth line.
    sed -i "1i"nr"\t"nr_current"\t"$most_recent_path/$nr_id $loc_path
    sed -i "2i"human_nr_$dateMostRecentDownload"\t"human_nr_current"\t"$most_recent_path/$h_id $loc_path
    sed -i "3i"mouse_nr_$dateMostRecentDownload"\t"mouse_nr_current"\t"$most_recent_path/$m_id $loc_path
else
    # Nc replaces the Nth line.
    sed -i "1cnr\tnr_current\t$most_recent_path\/$nr_id" $loc_path
    sed -i "2chuman_nr_$dateMostRecentDownload\thuman_nr_current\t$most_recent_path\/$h_id" $loc_path
    sed -i "3cmouse_nr_$dateMostRecentDownload\tmouse_nr_current\t$most_recent_path\/$m_id" $loc_path
fi

sed -i "4i"$nr_line $loc_path
sed -i "5i"$h_line $loc_path
sed -i "6i"$m_line $loc_path

# print lines 1 to 15 (drops old databases, if they exist)
sed -i -n '1,15p' $loc_path

#=========================================#
#     Step 3: Update the download times   #
#=========================================#
nLines=$(wc -l $mostRecentDatesPath)

# if we have downloaded 4 or more databases, then delete oldest. else, do nothing
if [ nLines -gt 3 ]: then
    # get oldest database (most recent date file is a queue, so first line)
    oldestDB=$(head -n 1 $mostRecentDatesPath)
    rm -r $db_path/$oldestDB

    # rewrite mostRecentDates.txt to remove oldest file
    sed -i '1!p' $mostRecentDatesPath
fi


