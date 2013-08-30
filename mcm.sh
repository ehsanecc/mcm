#!/bin/bash

printf "IMDb Collection Manager v1.1 by Ehsan Varasteh\n\n"

declare nochange="" debug="" exact="" fformat="%title %year"
declare movie="" title=""

while getopts "hndxf:" SWITCH; do
	case "$SWITCH" in
	h)
	 echo -e "\t-h       shows help\n"\
	 		 "\t-d       debug mode\n"\
	 		 "\t-x       exact match mode(don't modify anything unless exact match title)\n"\
	 		 "\t-n       no modify at any case\n"\
	 		 "\t-f <arg> folder format(default: \"%title %year\")\n"\
	 		 "\t         values: %title %year %rate %genres %director %writer %actors";
	 exit ;;
	n) nochange=1 ;;
	d) debug=1 ;;
	x) exact=1 ;;
	f) if [ -z "$(echo "$OPTARG" | grep -o -P '%(title|year|rate|genres|director|writer|actors)')" ]; then
	     echo -e "WARNING! no dynamic value set in folder format,\n this will rename all your folders to '$OPTARG'!!"
	     exit
	   else
	     fformat="$OPTARG"
	   fi
	 ;;
	?) echo "Unknown option '$SWITCH'"; exit ;;
	esac
done

function get_infos {
	local links="" src="" titles="" i=1

	exact_match=""
	links=$(wget -q -O - "http://www.imdb.com/find?q=$(perl -e "use URI::Escape; print(uri_escape(\"@ARGV[0]\"));" "$movie")&s=tt" | grep -o "result_text\">[^>]*>[^>]*>" | sed "s/result_text\"> \?//g")
	titles=$(echo "$links" | sed "s/[^>]*>\([^<]*\).*/\1/g")
	# this for loop will look up for exact match ( title to title )
	while [ -n "$(echo "$titles" | sed -n ${i}p)" ]; do
		if [ "$(echo $movie | tr "[A-Z]" "[a-z]" | tr -d -c "[a-z ]" | sed "s/ *$//g")" == "$(echo "$titles" | sed -n ${i}p | tr "[A-Z]" "[a-z]" | tr -d -c "[a-z ]" | sed "s/ *$//g")" ]; then
			title=$(echo "$titles" | sed -n ${i}p)
			link=$(echo "$links" | sed -n ${i}p | sed "s/[^\"]*\"\([^\"]*\).*/\1/g")
			exact_match=1
			break
		fi
		let "i++"
	done
	if [ -z "$link" ]; then link=$(printf "$links" | sed -n 1p | sed "s/[^\"]*\"\([^\"]*\).*/\1/g"); fi # pick first result (trust imdb result)
	if [ -n "$debug" ]; then echo -e "\n..link=http://www.imdb.com$link"; fi
	src="$(wget -q -O - "http://www.imdb.com$link")"
	title=$(echo "$src" | grep -o -P "itemprop=\"name\">[^<]*" | sed "s/.*>\([^\"]*\).*/\1/g" | sed -n 1p | sed "s/\&quot//g;s/\;//g")
	if [ "$title" != "" ]; then
		year=$(echo "$src" | grep "/year/" | sed "s/.*\/year\/\([^\/]*\).*/\1/")
		if [ -z "$year" ]; then year=$(echo "$src" | grep -o -P "<meta property=('|\")og:title('|\") content=\"[^>]*" | sed "s/.*content=\"\([^\"]*\).*/\1/g;s/.*(\([0-9]*\))$/\1/g"); fi
		# year clearance
		year=$(echo "$year" | sed "s/\&quot//g;s/\;//g" | tr -d -c "[0-9-]" | sed 's/^[^0-9]*//g;s/[^0-9]*$//g')
		rating=$(echo "$src" | grep -o -P "ratingValue\">[^<]*" | sed "s/[^>)]*>\([^<]*\).*/\1/" | tr -d -c "[0-9,.]")
		genres=$(echo "$src" | grep -o -P "itemprop=\"genre\" ?>[^<]*" | sed "s/.*\"genre\">\([^<]*\).*/\1/g" | tr "\n" "," | sed "s/,*$//;s/,/, /g")
		directors=$(echo "$src" | grep -o -P "tt_ov_dr\"[^>]*>[^>]*>[^>]*>" | sed "s/.*\"name\">\([^<]*\).*/\1/g" | tr "\n" "," | sed "s/,*$//;s/,/, /g")
		writers=$(echo "$src" | grep -o -P "tt_ov_wr\"[^>]*>[^>]*>[^>]*>" | sed "s/.*\"name\">\([^<]*\).*/\1/g" | tr "\n" "," | sed "s/,*$//;s/,/, /g")
		actors=$(echo "$src" | grep -o -P "tt_ov_st\"[^>]*>[^>]*>[^>]*>" | sed "s/.*\"name\">\([^<]*\).*/\1/g" | tr "\n" "," | sed "s/,*$//;s/,/, /g")
		description=$(echo "$src" | grep -o -P "<meta property=('|\")og:description('|\") content=\"[^>]*" | sed "s/.*content=\"\([^\"]*\).*/\1/g;s/\&quot//g;s/\;//g")
		poster=$(echo "$src" | grep -o -P "<meta property=('|\")og:image('|\") content=\"[^>]*" | sed "s/.*content=\"\([^\"]*\).*/\1/g" | grep -o -P ".*@@").jpg
	fi
	
	if [ -n "$debug" ]; then
		echo -e "\n..year=$year\n..rating=$rating\n..genres=$genres\n..directors=$directors\n..writers=$writers\n..actors=$actors\n..description=$description\n..poster=$poster";
		tmpfile=$(tempfile)
		echo "$src" > "$tmpfile"
		echo "page is in $tmpfile"
	fi
};


readarray movie_list <<< "$(ls -1)"
for movie in "${movie_list[@]%?}"; do
	printf "> $movie <==> ...\b\b\b"
	get_infos
	title_clr="$(echo "$title" | tr "/:" "--")"
	if [ -z "$title" ]; then
		printf "not in IMDB database <\n"
		continue
	fi
	printf "$title $year [$rating]\n"
	
	if [ -z "$nochange" ]; then
		if ([ -n "$exact" ] && [ -n "$exact_match" ]) || [ -z "$exact" ]; then
			mdir="$movie"
			desiredir=$(echo $fformat | sed "s/%title/$title_clr/gi;s/%year/$year/gi;s/%rate/$rating/gi;s/%genres/$genres/gi;s/%director/${directors%%,*}/gi;s/%writer/${writers%%,*}/gi;s/%actors/$actors/gi")
			if [ ! -d "$mdir" ]; then
				mkdir "$desiredir"
				mv "$movie" "$desiredir"
				mdir="$desiredir"
			fi
			if [ "$mdir" != "$desiredir" ]; then
				mv -n "$mdir" "$desiredir";
				mdir="$desiredir"
			fi
			if [ ! -e "$mdir/index.jpg" ]; then
				wget -q -O - "$poster" > "$mdir/index.jpg"
			fi
			printf "$title ($year) [$rating]\n\nDescription: $description\nDirectors: $directors\nGenres: $genres\nCast: $actors\nIMDb Link: http://www.imdb.com$link\n" > "$mdir/info.nfo"
		fi
	fi
done

echo "job done!"


