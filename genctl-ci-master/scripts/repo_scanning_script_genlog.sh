#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## © Copyright IBM Corp. 2019
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##


# This Script is for checking if the use of context object as first paramter 
# is enforced in the source directories of each workspace. It also reports the usage 
# of genlog for logging in a summarized version on the screen as well as a verbose report 
# in a text file in the tmp directory  

OUTPUT_PATH=/tmp

function main() {

    if [[ ( "$1" == "--help") ||  "$1" == "-h" || -z "$1" ]]; then 
        display_usage
	exit 0
    fi
    
    
    if [[ ( "$2" == "-v") ||  "$2" == "--verbose" ]]; then 
        count_logging_calls_per_microservice "$1" "$2" 
        report_defer_logger_dot_sync_usage "$1" "$2"
    else
        count_logging_calls_per_microservice "$1"
    fi
    
}


function check_if_genlog_is_imported() {
    counter=0
    while IFS='' read -r line || [[ -n "$line" ]]; do
        num_lines_in_import_block=$(sed -n '/import (/,/)/p' "$1" | wc -l)
        line_without_trailing_spaces=$(echo "$line" | sed -e 's/^[ \t]*//')
        counter=$((counter + 1))
        if [[ "$line_without_trailing_spaces" =~ \".*genlog\" ]] || [[ "$line_without_trailing_spaces" =~ \".*logging\" ]]; then
            echo TRUE
            break
        else
            if [[ $counter == $num_lines_in_import_block ]]; then
                echo FALSE
                break
            fi
         fi
    done < <(sed -n '/import (/,/)/p' "$1")
}


function check_if_zap_is_imported() {
    counter=0
    while IFS='' read -r line || [[ -n "$line" ]]; do
        num_lines_in_import_block=$(sed -n '/import (/,/)/p' "$1" | wc -l)
        line_without_trailing_spaces=$(echo "$line" | sed -e 's/^[ \t]*//')
        counter=$((counter + 1))
        if [[ "$line_without_trailing_spaces" =~ \".*zap\" ]] || [[ "$line_without_trailing_spaces" =~ \".*zapcore\" ]]; then
            echo TRUE
            break
        else
            if [[ $counter == $num_lines_in_import_block ]]; then
                echo FALSE
                break
            fi
         fi
    done < <(sed -n '/import (/,/)/p' "$1")
}


function check_if_native_logger_is_imported() {
    counter=0
    while IFS='' read -r line || [[ -n "$line" ]]; do
        num_lines_in_import_block=$(sed -n '/import (/,/)/p' "$1" | wc -l)
        line_without_trailing_spaces=$(echo "$line" | sed -e 's/^[ \t]*//')
        counter=$((counter + 1))
        if [[ "$line_without_trailing_spaces" =~ \"log\" ]]; then
            echo TRUE
            break
        else
            if [[ $counter == $num_lines_in_import_block ]]; then
                echo FALSE
                break
            fi
         fi
    done < <(sed -n '/import (/,/)/p' "$1")

}


function check_if_logrus_is_imported() {
    counter=0
    while IFS='' read -r line || [[ -n "$line" ]]; do
        num_lines_in_import_block=$(sed -n '/import (/,/)/p' "$1" | wc -l)
        line_without_trailing_spaces=$(echo "$line" | sed -e 's/^[ \t]*//')
        counter=$((counter + 1))
        if [[ "$line_without_trailing_spaces" =~ \".*logrus\" ]]; then
            echo TRUE
            break
        else 
            if [[ $counter == $num_lines_in_import_block ]]; then
                echo FALSE
                break
            fi
        fi
    done < <(sed -n '/import (/,/)/p' "$1")

}


function count_logrus_calls_per_file() {
    logrus_calls_count=0
    while IFS='' read -r line || [[ -n "$line" ]]; do
        if [[ $line == "^//*" ]]; then
            :
        else
            if [[ $line == *.Info* ]] || [[ $line == *.Error* ]] || [[ $line == *.Debug* ]] || [[ $line == *.Fatal* ]] || [[ $line == *.Warn* ]] || [[ $line == *.InfoAudit* ]]; then
                logrus_calls_count=$((logrus_calls_count + 1))
            fi
        fi

    done < "$1"
    echo $logrus_calls_count

}


function count_genlog_logging_calls_per_file() {
    genlog_calls_count=0
    while IFS='' read -r line || [[ -n "$line" ]]; do
        if [[ $line == "^//*" ]]; then
            :
        else
            if [[ $line == *.Info* ]] || [[ $line == *.Error* ]] || [[ $line == *.Debug* ]] || [[ $line == *.Fatal* ]] || [[ $line == *.Warn* ]] || [[ $line == *.InfoAudit* ]]; then
                genlog_calls_count=$((genlog_calls_count + 1))
            fi
        fi

    done < "$1"
    echo $genlog_calls_count


}


function count_native_calls_per_file() {
    native_calls_count=0
    while IFS='' read -r line || [[ -n "$line" ]]; do
        line=$(echo "$line" | sed -e 's/^[ \t]*//')
        if [[ $line == "^//*" ]]; then
            :
        else
            if [[ "$line" == log.Info* ]] || [[ "$line" == log.Error* ]] || [[ "$line" == log.Debug* ]] || [[ "$line" == log.Fatal* ]] || [[ "$line" == log.Printf* ]] || [[ "$line" == log.Warn* ]]; then
                native_calls_count=$((native_calls_count + 1))
            fi
        fi

    done < "$1"
       echo $native_calls_count

}


function count_zap_calls_per_file() {
    zap_calls_count=0
    while IFS='' read -r line || [[ -n "$line" ]]; do
        line=$(echo "$line" | sed -e 's/^[ \t]*//')
        if [[ $line == "^//*" ]]; then
            :
        else 
            if [[ $line == *.Info* ]] || [[ $line == *.Error* ]] || [[ $line == *.Debug* ]] || [[ $line == *.Fatal* ]] || [[ $line == *.Warn* ]]; then
                zap_calls_count=$((zap_calls_count + 1))
            fi
        fi

    done < "$1"
       echo $zap_calls_count
}


function check_if_defer_logger_dot_sync_is_defined_after_genlog() {
    sync=YES
    nosync=NO
    logger=genlog
    line_counter=0
    while read LINE1
    do
        if [[ "$LINE1" == *genlog.New* ]] || [[ "$LINE1" == *handler.Logger.With\( ]]; then
            line_counter=$((line_counter + 1))

            # read the next line that follows genlog definition
            read LINE2

            # check if the line has *defer* with *logger.Sync* defined 
            if [[ "$LINE2" == *.Sync\(\) ]]; then
                line_counter=$((line_counter + 1))
                printf "%5s : %10s : %30s\n" $sync $logger "$1 on line $line_counter" >> $OUTPUT_PATH/scanning_result_verbose.txt 
            else
                read LINE3
                if [[ "$LINE3" == *.Sync\(\) ]]; then
                    line_counter=$((line_counter + 2))
                    printf "%5s : %10s : %30s\n" $sync $logger "$1 on line $line_counter" >> $OUTPUT_PATH/scanning_result_verbose.txt
                else
                    read LINE4
                    if [[ "$LINE4" == *.Sync\(\) ]]; then
                        line_counter=$((line_counter + 3))
                        printf "%5s : %10s : %30s\n" $sync $logger "$1 on line $line_counter" >> $OUTPUT_PATH/scanning_result_verbose.txt
                    else
                        read LINE5
                        if [[ "$LINE5" == *.Sync\(\) ]]; then
                            line_counter=$((line_counter + 4))
                            printf "%5s : %10s : %30s\n" $sync $logger "$1 on line $line_counter" >> $OUTPUT_PATH/scanning_result_verbose.txt
                        else
                            read LINE6
                            if [[ "$LINE6" == *.Sync\(\) ]]; then
                                line_counter=$((line_counter + 5))
                                printf "%5s : %10s : %30s\n" $sync $logger "$1 on line $line_counter" >> $OUTPUT_PATH/scanning_result_verbose.txt
                            else
                                read LINE7
                                if [[ "$LINE7" == *.Sync\(\) ]]; then
                                    line_counter=$((line_counter + 6))
                                    printf "%5s : %10s : %30s\n" $sync $logger "$1 on line $line_counter" >> $OUTPUT_PATH/scanning_result_verbose.txt
                                elif [[ "$LINE7" != *.Sync\(\) ]]; then
                                    read LINE8
                                        read LINE9
                                            read LINE10
                                                read LINE11
                                                    read LINE12
                                                        read LINE13
                                                            read LINE14
                                                                read LINE15
                                                                    read LINE16
               							        read LINE17
                                                                        if [[ "$LINE17" == *.Sync* ]]; then
                                                                            line_counter=$((line_counter + 18))
                                                                            printf "%5s : %10s : %30s\n" $sync $logger "$1 on line $line_counter" >> $OUTPUT_PATH/scanning_result_verbose.txt
                                                                        fi
                                else
                                    printf "%5s : %10s : %30s\n" $nosync $logger "$1 on line $line_counter" >> $OUTPUT_PATH/scanning_result_verbose.txt
                                fi
                            fi
                        fi
                    fi
                fi
            fi
        else
            line_counter=$((line_counter + 1))
        fi
    done < $1
}


function count_logging_calls_per_microservice() {
    
    total_genlog_calls=0
    native_log_count=0  
    zap_log_count=0
    fmt_log_count=0


    nolog=NA
    goodLogging=genlog

    if [[ "$2" == "-v" || "$2" == "--verbose" ]]; then
        repo=$(echo "$1" | sed 's:/.*::')
        echo "GENLOG USAGE COVERAGE ($repo)" >> $OUTPUT_PATH/scanning_result_verbose.txt
        file=FILE
        library=LIBRARY
        usage="%USAGE"
        printf "%6s : %10s : %30s\n" $usage $library $file >> $OUTPUT_PATH/scanning_result_verbose.txt
        echo "----------------------------------------------------------------------------------------------------------------------------------" >> $OUTPUT_PATH/scanning_result_verbose.txt
    fi    

    for file in $(find "$1" -name "*.go"); do
        if [[ $file == *test* ]] || [[ $file == *logger.go ]] || [[ $file == *mediary.go ]] || [[ $file == *demo* ]] || [[ $file == */vendor/* ]]; then
            :
        elif [[ $file == *"shared-logger"* ]]; then 
            :
        else
            
            is_logrus_imported=$(check_if_logrus_is_imported "$file")
            is_genlog_imported=$(check_if_genlog_is_imported "$file")
            if [[ $is_genlog_imported == TRUE ]] || [[ $is_logrus_imported == TRUE ]]; then
                total_logging_calls_per_file_with_genlog=0
                genlog_calls_count_per_file=$(count_genlog_logging_calls_per_file "$file")
                
                if [[ "$genlog_calls_count_per_file" -ne "0"  ]]; then
                    total_genlog_calls=$(($total_genlog_calls+$genlog_calls_count_per_file))
                    total_logging_calls_per_file_with_genlog=$(($total_logging_calls_per_file_with_genlog+$genlog_calls_count_per_file))
           
                    is_native_logger_imported=$(check_if_native_logger_is_imported "$file")
                    if [[ $is_native_logger_imported == TRUE ]]; then
                        native_logging_calls_count_per_file=$(count_native_calls_per_file "$file")
                        if [[ "$native_logging_calls_count_per_file" -ne "0"  ]]; then   
                            native_log_count=$(($native_log_count+$native_logging_calls_count_per_file))
                            total_logging_calls_per_file_with_genlog=$(($total_logging_calls_per_file_with_genlog+$native_logging_calls_count_per_file))
                        fi
                        
                    fi

                 
                    fmtprint_logging_calls_per_file=$(grep -v "//" "$file" | grep -v "*" | grep "fmt.Printf" | wc -l) 
                    if [[ "$fmtprint_logging_calls_per_file" -ne "0"  ]]; then
                        fmt_log_count=$(($fmt_log_count+$fmtprint_logging_calls_per_file))
                        total_logging_calls_per_file_with_genlog=$(($total_logging_calls_per_file_with_genlog+$fmtprint_logging_calls_per_file))
                    fi

                    # For a verbose report
                    if [[ "$2" == "-v" || "$2" == "--verbose" ]]; then

                        percentage=$(awk "BEGIN {printf \"%.2f\",($genlog_calls_count_per_file/$total_logging_calls_per_file_with_genlog) * 100}")
                        printf "%.2f : %10s : %30s\n" $percentage $goodLogging "$file" >> $OUTPUT_PATH/scanning_result_verbose.txt                        

 
                        if [[ "$native_logging_calls_count_per_file" -eq "0" ]] && [[ "$fmtprint_logging_calls_per_file" -eq "0" ]] && [[ "$genlog_calls_count_per_file" -eq "0" ]]; then
                            printf "%3s : %10s : %30s\n" $nolog $nolog "$file" >> $OUTPUT_PATH/scanning_result_verbose.txt
                        fi


                        is_native_logger_imported=$(check_if_native_logger_is_imported "$file")
                        if [[ $is_native_logger_imported == TRUE ]]; then
			    native_logging_calls_count_per_file=$(count_native_calls_per_file "$file")
                            naLogging=nativeLogging
                            percentage=$(awk "BEGIN {printf \"%.2f\",($native_logging_calls_count_per_file/$total_logging_calls_per_file_with_genlog) * 100}")
                            printf "%.2f : %10s : %30s\n" $percentage $naLogging "$file" >> $OUTPUT_PATH/scanning_result_verbose.txt
                        fi

                       
 
                        if [[ "$fmtprint_logging_calls_per_file" -ne "0" ]]; then
                            fmLogging=fmtLogging
                            percentage=$(awk "BEGIN {printf \"%.2f\",($fmtprint_logging_calls_per_file/$total_logging_calls_per_file_with_genlog) * 100}")
                            printf "%.2f : %10s : %30s\n" $percentage $fmLogging "$file" >> $OUTPUT_PATH/scanning_result_verbose.txt
                        fi
                    fi
                else
                    if [[ "$2" == "-v" || "$2" == "--verbose"  ]]; then
                        printf "%3s : %10s : %30s\n" $nolog $goodLogging "$file" >> $OUTPUT_PATH/scanning_result_verbose.txt
                    fi
                fi
            else
                total_logging_calls_per_file_without_genlog=0 
                native_logging_calls_count_per_file=0
                zap_logging_calls_per_file=0
                fmtprint_logging_calls_per_file=0

                is_native_logger_imported=$(check_if_native_logger_is_imported "$file")
                if [[ $is_native_logger_imported == TRUE ]]; then
                    native_logging_calls_count_per_file=$(count_native_calls_per_file "$file")
                    if [[ "$native_logging_calls_count_per_file" -ne "0"  ]]; then
                        native_log_count=$(($native_log_count+$native_logging_calls_count_per_file))
                        total_logging_calls_per_file_without_genlog=$(($total_logging_calls_per_file_without_genlog+$native_logging_calls_count_per_file))
                    fi
                fi
   

                is_zap_imported=$(check_if_zap_is_imported "$file")
                if [[ $is_zap_imported == TRUE ]]; then
                    zap_logging_calls_per_file=$(count_zap_calls_per_file "$file")
                    if [[ "$zap_logging_calls_per_file" -ne "0"  ]]; then
                        zap_log_count=$(($zap_log_count+$zap_logging_calls_per_file))
                        total_logging_calls_per_file_without_genlog=$(($total_logging_calls_per_file_without_genlog+$zap_logging_calls_per_file))
                    fi
                fi


                fmtprint_logging_calls_per_file=$(grep -v "//" "$file" | grep -v "*" | grep "fmt.Printf" | wc -l)
                if [[ "$fmtprint_logging_calls_per_file" -ne "0"  ]]; then
                    fmt_log_count=$(($fmt_log_count+$fmtprint_logging_calls_per_file))
                    total_logging_calls_per_file_without_genlog=$(($total_logging_calls_per_file_without_genlog+$fmtprint_logging_calls_per_file))
                fi


                # For a verbose report in files without genlog               
                if [[ "$2" == "-v" ]] || [[ "$2" == "--verbose" ]]; then
                   
                    if [[ "$native_logging_calls_count_per_file" -eq "0" ]] && [[ "$zap_logging_calls_per_file" -eq "0" ]] && [[ "$fmtprint_logging_calls_per_file" -eq "0" ]]; then 
                        printf "%3s : %10s : %30s\n" $nolog $nolog "$file" >> $OUTPUT_PATH/scanning_result_verbose.txt
                    fi
                    
                    is_native_logger_imported=$(check_if_native_logger_is_imported "$file")
                    if [[ $is_native_logger_imported == TRUE ]]; then
                        native_logging_calls_count_per_file=$(count_native_calls_per_file "$file")
     
                        if [[ "$native_logging_calls_count_per_file" -ne "0" ]] && [[ "$total_logging_calls_per_file_without_genlog" -ne "0" ]]; then 
                            badlog=nativeLogger
                            percentage=$(awk "BEGIN {printf \"%.2f\",($native_logging_calls_count_per_file/$total_logging_calls_per_file_without_genlog) * 100}")
                            printf "%.2f : %10s : %30s\n" $percentage $badlog "$file" >> $OUTPUT_PATH/scanning_result_verbose.txt
                        fi
                    fi
                    

                    is_zap_imported=$(check_if_zap_is_imported "$file")
                    if [[ $is_zap_imported == TRUE ]]; then
                        zap_logging_calls_per_file=$(count_zap_calls_per_file "$file")

                        if [[ "$zap_logging_calls_per_file" -ne "0" ]] && [[ "$total_logging_calls_per_file_without_genlog" -ne "0" ]]; then
                            badlog=zap
                            percentage=$(awk "BEGIN {printf \"%.2f\",($zap_logging_calls_per_file/$total_logging_calls_per_file_without_genlog) * 100}")
                            printf "%.2f : %10s : %30s\n" $percentage $badlog "$file" >> $OUTPUT_PATH/scanning_result_verbose.txt
                        fi
                    fi


                    if [[ "$fmtprint_logging_calls_per_file" -ne "0" ]] && [[ "$total_logging_calls_per_file_without_genlog" -ne "0" ]]; then
                        badlog=fmtPrint
                        percentage=$(awk "BEGIN {printf \"%.2f\",($fmtprint_logging_calls_per_file/$total_logging_calls_per_file_without_genlog) * 100}")
                        printf "%.2f : %10s : %30s\n" $percentage $badlog "$file" >> $OUTPUT_PATH/scanning_result_verbose.txt
                    fi
                fi
            fi

        fi
    done

    total_logging_calls=$(($total_genlog_calls+$native_log_count+$zap_log_count+$fmt_log_count))   
    repo=$(echo "$1" | sed 's:/.*::')
    if [ -z "$2" ]; then 
        echo "GENLOG USAGE COVERAGE ($repo):" 
        echo "--------------------------------------------------"
        echo "  TOTAL GENLOG CALLS: $total_genlog_calls"
        echo "  TOTAL LOGGING CALLS: $total_logging_calls"
        if [[ "$total_logging_calls" -ne "0" ]]; then 
            percentage=$(awk "BEGIN {printf \"%.2f\",($total_genlog_calls/$total_logging_calls) * 100}")
        fi
        echo "  GENLOG USAGE COVERAGE: $percentage%"
        echo "--------------------------------------------------"
    fi

}


function report_defer_logger_dot_sync_usage() {
     if [[ "$2" == "-v" || "$2" == "--verbose" ]]; then
        repo=$(echo "$1" | sed 's:/.*::')
        echo >> $OUTPUT_PATH/scanning_result_verbose.txt
        echo "DEFER SYNC USAGE REPORT ($repo)" >> $OUTPUT_PATH/scanning_result_verbose.txt
        file=FILE
        library=LIBRARY
        usage="is_SYNC"
        printf "%7s : %10s : %30s\n" $usage $library $file >> $OUTPUT_PATH/scanning_result_verbose.txt
        echo "----------------------------------------------------------------------------------------------------------------------------------" >> $OUTPUT_PATH/scanning_result_verbose.txt
    fi
     
    for file in $(find "$1" -name "*.go"); do
        if [[ $file == *test.go ]] || [[ $file == */vendor/* ]]; then
            :
        elif [[ $file == *"shared-logger"* ]]; then
            :
        else
            if [[ "$2" == "-v" || "$2" == "--verbose" ]]; then
                is_logrus_imported=$(check_if_logrus_is_imported "$file")
                is_genlog_imported=$(check_if_genlog_is_imported "$file")
                if [[ $is_genlog_imported == TRUE ]] || [[ $is_logrus_imported == TRUE ]]; then
                    check_if_defer_logger_dot_sync_is_defined_after_genlog "$file"
                fi
            fi
        fi
    
    done < $1 

}


display_usage() {
    echo -n "Usage: "
    Usage="/$(basename "$0") <repo_path/src> [option]
    Parameters:
      - repo_path/src: repo source directory
    Options:
      - option: -v or --verbose

    For example: ./repo_scanning_script.sh security-service-workspace/src (by default) 
                 ./repo_scanning_script.sh security-service-workspace/src -v or --verbose (check /tmp/scanning_result_verbose.txt for output)"

    echo "$Usage"
}


trap 'kill ""$bgid""' EXIT

main "$1" "$2" &

jobid=$!

while :; do
printf "".""
sleep 1
done &

## store the background process's ID 
bgid=$!

wait ""$jobid""
