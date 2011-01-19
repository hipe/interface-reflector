### usage

rs ../img/aha/* -o "{path}" -m "{dirname}/full/{basename}" -ranp -w600 -e450


This moves each of the source images into the directory called 'full', effectively replacing them with smaller versions of themselves per the dimensions "-w" and "-h".  The images scaled down to fit *within* the dimensions while maintaining aspect ratio.  (So each dimension of each resulting image is guaranteed to be *at most* that value but may be smaller depending on the dimensions of the image.)

-m indicates where to move the source files, if any.  Two macros are used: "dirname" and "basename."  These are derived from the current input file.

-o indicates where to put each generated image file.  In this case the "path" macro is used, which means "use the same name as the input file," i.e. replace it.  However because we are moving the input file with the -m option, the original file will be intact.

-p will create directories as needed, in our case the "full" directory if it does not exist.

-r means recursive, that is, descend into directories.

-a will maintain aspect ratio, rather than possibly distorting the image, while keeping the resulting image within the bounds specified by -w and -h

-n is --dry-run, i.e. don't do anything.