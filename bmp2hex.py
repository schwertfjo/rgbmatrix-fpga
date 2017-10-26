#!/usr/bin/env python

__author__ = "Anastasis Keliris"
__licence__ = "MIT"

# Imports
from subprocess import call
import os, sys
from optparse import OptionParser
import os
from scipy import misc



def ihex_csum(hex_data):
    """
    Compute Intel Hex checksum of all bytes of a line of hex. The hex_data is a
    hex string of data, without checksum.
 
    >>> ihex_csum("0C00000000020B11129B12000B66EAE7")
    213
     
    """
    hex_bytes = [ord(b) for b in hex_data.decode("hex")]
    csum = sum(hex_bytes) & 0xFF
    csum = ((csum ^ 0xFF) + 1) & 0xFF
    return csum


def main(argv):
    '''
    Main function: Parses command line arguments and updates checksum
    '''

    parser = OptionParser()
    parser.add_option("-i", "--input", dest="inputfile",
                      help="Input file for checksum verification", default = None)
    parser.add_option("-o", "--output", dest="outputfile",
                      help="Output file with valid checksum", default = None)
    parser.add_option("-r", action="store_true", dest="remout",
                      help="Delete output file")
       
    # Get command line arguments                  
    (options, args) = parser.parse_args()
    
    # Check arguments
    if not options.inputfile:
            parser.print_help()
            sys.exit(1)
    
    infile = options.inputfile
    if options.remout:
        del_output = True
    else:
        del_output = False
    if not options.outputfile:
        outfile = os.path.splitext(infile)[0] + "_vld" + ".hex"
    else:
        outfile = options.outputfile


    # Variable init
    linecount = 0
    bytecount = "03"

    # Open files
    path = './'
    image= misc.imread(os.path.join(path, infile), flatten= 0, mode= 'RGB')
    f_out = open(outfile,'w')

    l = 0
    a = 0
    ll= 256
    for line in image:
        for rgb in line:
            address = '{:04X}'.format(l*ll+a)
            r,g,b = rgb[0], rgb[1], rgb[2]
            pixelValue = '{:02X}'.format(r) + '{:02X}'.format(g) + '{:02X}'.format(b)
            cmd = bytecount + address + "00" + pixelValue
            chk =  '{:02X}'.format(ihex_csum(cmd))
            f_out.write(":"+cmd + chk+"\n")
            a += 1

        while a % ll:
            address = '{:04X}'.format(l*ll+a)
            r,g,b = 0, 0, 0
            pixelValue = '{:02X}'.format(r) + '{:02X}'.format(g) + '{:02X}'.format(b)
            cmd = bytecount + address + "00" + pixelValue
            chk =  '{:02X}'.format(ihex_csum(cmd))
            f_out.write(":"+cmd + chk+"\n")
            a += 1

        l += l
    f_out.write(":00000001FF")
    f_out.close()


# Call main with command line arguments
if __name__ == "__main__":
    main(sys.argv[1:])
