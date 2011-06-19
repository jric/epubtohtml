#!/usr/bin/perl -W
#
# Converts an epub document into a document that can be natively read by a web-browser.
#
# Algorithm:
#
# * Unzip epub file
# * do text substitutions as necessary
# * create a navigation index
#
# Copyright 2011 Joshua Richardson, Chegg Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
   
use Getopt::Long;
use XML::Simple;
use Data::Dumper;

my($help, $outdirectory, $base_fn, $opfxml);
my($PROG) = $0 =~ m@/([^/]+)$@;

sub usage { 
        print STDERR "$0 usage:\n";
        print STDERR "\t$PROG [options] <filename>\n";
        print STDERR "\t-h|--help : print usage info\n";
        print STDERR "\t-o|--out : output directory\n";
}

# Initialize
Getopt::Long::Configure ("bundling");

# Process commandline options
my($args_ok, $nonoption_args) = GetOptions ('help|h' => \$help, 'out|o=s' => \$outdirectory);
$nonoption_args = \@ARGV;

if (!$args_ok) { usage(); die "failed to process options"; }
if (!defined($nonoption_args)) { usage(); die "missing required args"; }

my($inputfilename, @unexpected_args) = @$nonoption_args;
if (!defined($inputfilename)) { usage(); die('not enough args'); }
if (@unexpected_args) { usage(); die('too many args'); }
if (defined($outdirectory) && -e $outdirectory && ! -d $outdirectory)
{ usage(); die("$outdirectory is not a directory"); }
if (defined($help)) { usage(); exit(0); }

if (!defined($outdirectory)) {
	# Set the output directory == input directory/epubfilename without epub extension
	($outdirectory, $filename_ext) = $inputfilename =~ m@(.+)\.([^.]+)$@;
	if (!defined($filename_ext) || lc($filename_ext) ne 'epub')
	{ die("\"$inputfilename\" does not have a recognized epub file extension."); }
}
($base_fn) = $inputfilename =~ m@([^./]+)\.[^.]+$@;
if (!defined($base_fn)) { die "Unable to get base of the filename"; }

# Unzip epub file
my($UNZIP_CMD) = "unzip -d $outdirectory $inputfilename";

system($UNZIP_CMD) && die("failed ($!): $UNZIP_CMD");

# Process epub files
opendir(DIR, $outdirectory) || die("Cannot open directory \"$outdirectory\"");
my(@epub_files) = grep(!m/^\./, readdir(DIR)); # filter out hidden files
closedir(DIR);

## Process html files
my(@html_files) = map("$outdirectory/$_", grep(m/\.x?html/i, @epub_files));
processHtmlFiles(\@html_files) && die("failed to process the html files");

## Create navigation
my($opfn) = grep(m/.opf$/, @epub_files);
if (!defined($opfn))
{ print STDERR "$PROG: WARN: No opf file to get meta-data; will not create index.\n"; exit 0; }
parseOPF($opfn) && do { print STDERR "$PROG: ERROR: Unable to parse $opfn.\n"; exit 1; };
(createIndexFile() || createFrames()) && print STDERR "$PROG: WARN: Failed to create index file.\n";

sub createFrames {
	my($first_page_id) = $opfxml->{'spine'}->{'itemref'}->[0]->{'idref'};
	if (!defined($first_page_id))
	{ print STDERR "$PROG: ERROR: Failed to find first content page in OPF spine, $opfn\n"; return 1; }

	my($first_page) = $opfxml->{'manifest'}->{'item'}->{$first_page_id}->{'href'};
	
	my($debug) = $opfxml->{'manifest'}->{'item'};
	print Dumper($debug, $first_page_id);

	if (!defined($first_page))
	{ print STDERR "$PROG: ERROR: Failed to find named content page in OPF, $opfn\n"; return 1; }

	my $data = <<END
<!DOCTYPE HTML>
<HTML>
<HEAD>
<TITLE></TITLE>
<META http-equiv="Content-Type" content="text/html; charset=UTF-8">
<META name="generator" content="epubtohtml 1.0">
</HEAD>
<FRAMESET cols="100,*">
<FRAME name="navigation" src="index_idx.html">
<FRAME name="content" src="$first_page">
</FRAMESET>
</HTML>
END
;

	my($idx_fn) = "$outdirectory/index.html";
	if (-e $idx_fn) {
		print STDERR "$PROG: NOTICE: $idx_fn exists, using ";
		$idx_fn = "$outdirectory/index-epubtohtml.html";
		print STDERR "$idx_fn instead.\n";
	}
	open(IDX_F, ">$idx_fn") || die($!);
	print IDX_F $data;
	close(IDX_F) || die($!);
	
	return 0;
}

sub parseOPF {
	my($opfn) = @_;
	
	# Parse OPF
	$opfxml = XMLin("$outdirectory/$opfn");
	if (!defined($opfxml)) { print STDERR "$PROG: WARN: Failed to open/parse $opfn: $!\n"; return 1; }
	#print Dumper($opfxml);
	
	return 0;
}

sub createIndexFile {
	my($body) = '';

	# Parse OPF
	my $opfxml = XMLin("$outdirectory/$opfn");
	if (!defined($opfxml)) { print STDERR "$PROG: WARN: Failed to open/parse $opfn: $!\n"; return 1; }
	#print Dumper($opfxml);	
	
	# Create html body
	$body .= "<ul>\n";
	my($top_level) = $opfxml->{'spine'}->{'itemref'};
	if (!defined($top_level))
	{ print STDERR "$PROG: WARN: Unable to get spine.  Malformed OPF, $opfn?\n"; return 1; }
	foreach my $item (@$top_level) {
		my($text, $link) = $item->{'idref'};
		$link = $opfxml->{'manifest'}->{'item'}->{$text}->{'href'};
		if (!defined($link)) {
			print STDERR
			"$PROG: WARN: Unable to find item $text in manifest of $opfn.  Omitting $text from index.\n";
			next;
		}
		$body .= "\t<li><a href=\"$link\" target=\"content\">$text</a></li>\n";
	}
	$body .= "</ul>\n";
		
	# Create index html
	my($data) = <<END;
<!DOCTYPE HTML">
<html>

<head>
<title>Index for $opfxml->{'metadata'}->{'dc:title'}</title>
<style type="text/css">
body ul { padding: 0 }
</style>
</head>

<body>
$body
</body>

</html>
END
	my($idx_fn) = "$outdirectory/index_idx.html";
	if (-e "$outdirectory/index_idx.html")
	{ print STDERR "$PROG: WARN: $idx_fn already exists.  Unable to create index file.\n"; return 1; }
	open(IDX_F, ">$outdirectory/index_idx.html") || die($!);
	print IDX_F $data;
	close(IDX_F) || die($!);
	
	return 0;
}

sub processHtmlFile {
	my($filename) = @_;
	
	open(F, "<$filename") ||
		do { print STDERR "$PROG: WARN: failed to open $filename for reading.\n"; return 1; };
	my($data) = join('', <F>);
	close(F) || do { print STDERR "$PROG: WARN: failed to close $filename.\n"; return 2; };
	
	$data =~ s@text/x-oeb1-css@text/css@gi;
	
	open(F, ">$filename") ||
		do { print STDERR "$PROG: WARN: failed to open $filename for writing.\n"; return 3; };
	print F $data;
	close(F) || do { print STDERR "$PROG: WARN: failed to close $filename.\n"; return 4; };
	
	return 0;
}

sub processHtmlFiles {
	my($files) = @_;
	my($result) = 0;
	
	map($result += processHtmlFile($_), @$files);
	
	return $result;
}
