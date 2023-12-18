#!/usr/bin/bash

echo "building"

FILENAMES="vec_271_00_sv.dat vec_271_01_sv.dat vec_271_01_sv_short.dat vec_271_02_sv.dat vec_271_02_sv_short.dat vec_271_03_sv_short.dat"

TEST_SAMPS="1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37"

for n in $TEST_SAMPS
do 
	cp -r subs/$n/formal /home/users/sgautham/Desktop/rasterizer-fall-2023
	cp -r subs/$n/gold /home/users/sgautham/Desktop/rasterizer-fall-2023
	cp -r subs/$n/params /home/users/sgautham/Desktop/rasterizer-fall-2023
	cp -r subs/$n/rtl /home/users/sgautham/Desktop/rasterizer-fall-2023
	cp -r subs/$n/tests /home/users/sgautham/Desktop/rasterizer-fall-2023
    cp -r subs/$n/verif /home/users/sgautham/Desktop/rasterizer-fall-2023
        
    echo $n >> n.txt
	
	counter=0	
	make clean comp_gold

	for FILENAME in $FILENAMES
	do
	    echo -e "\n"
	    INPUT=$EE271_VECT/$FILENAME
	    OUTPUT={out.ppm}
	    REF=${INPUT/.dat/_ref.ppm}
	    echo "testing" $INPUT
	    echo "generating output" $OUTPUT
	    ./rasterizer_gold $OUTPUT $INPUT
	    echo "testing against reference" $REF
	    if diff $OUTPUT $REF;
	    then
            echo $INPUT passed
            ((counter++))
	    else
            echo $INPUT failed
            # exit 1
	    fi
	    echo "deleting output" $OUTPUT
	    rm -f $OUTPUT
	done
	
	echo $counter >> results.txt
	
	rm -r /home/users/sgautham/Desktop/rasterizer-fall-2023/formal
	rm -r /home/users/sgautham/Desktop/rasterizer-fall-2023/gold
	rm -r /home/users/sgautham/Desktop/rasterizer-fall-2023/params
	rm -r /home/users/sgautham/Desktop/rasterizer-fall-2023/rtl
	rm -r /home/users/sgautham/Desktop/rasterizer-fall-2023/tests
    rm -r /home/users/sgautham/Desktop/rasterizer-fall-2023/verif

done 

echo -e "\n"