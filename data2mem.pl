#!/usr/bin/perl

use strict;
use warnings;

my $data = 0;
my @data_list = ();
while (read(STDIN, $data, 1) == 1) {
	push(@data_list, ord($data));
}

my $data_length = @data_list;
if ($data_length > 65534) { $data_length = 65534; }

printf "%02X\n%02X\n", $data_length & 0xff, ($data_length >> 8) & 0xff;

for (my $i = 0; $i < 65534; $i++) {
	printf "%02X\n", $i < $data_length ? $data_list[$i] : 0;
}
