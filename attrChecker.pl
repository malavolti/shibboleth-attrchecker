#!/usr/bin/perl
use strict;
use warnings;

my $shib_config  = "/etc/shibboleth/shibboleth2.xml";
my $src_template = "/etc/shibboleth/attrChecker.orig.html";  # origin template
my $dst_template = "/etc/shibboleth/attrChecker.html";       # generated template used by SP

#
# 1) Read shibboleth2.xml and extract ONLY the attributes from the AttributeChecker handler
#
open(my $fh, '<', $shib_config) or die "Cannot read $shib_config: $!";
my $conf;
{ local $/; $conf = <$fh>; }
close $fh;

my $attr_str = '';
if ($conf =~ /<Handler[^>]*type=["']AttributeChecker["'][^>]*\battributes=["']([^"']+)["']/i) {
    $attr_str = $1;
} else {
    die "No AttributeChecker handler with attributes=\"...\" found in $shib_config\n";
}

# Normalize separators: allow both spaces and commas
$attr_str =~ s/,/ /g;
my @attrs = grep { $_ ne '' } split /\s+/, $attr_str;
@attrs = sort @attrs;

print "Attributes from AttributeChecker: ", join(", ", @attrs), "\n";

#
# 2) Load the ORIGINAL template (never modified)
#
-f $src_template or die "Source template $src_template not found\n";

open($fh, '<:encoding(UTF-8)', $src_template) or die "Cannot read $src_template: $!";
my $tpl;
{ local $/; $tpl = <$fh>; }
close $fh;

#
# IMPORTANT: We DO NOT touch any <shibmlp target /> tags.
# They are now driven by the 'target' attribute in <Errors> in shibboleth2.xml.
#

#
# 3) Regenerate ONLY the attribute table rows between <!--TableStart--> and <!--TableEnd-->
#
my $table_rows = "";
for my $attr (@attrs) {
    $table_rows .= "<tr <shibmlpifnot $attr> class='warning text-danger'</shibmlpifnot>>\n";
    $table_rows .= "        <th>$attr</th>\n";
    $table_rows .= "        <td><shibmlp $attr /></td>\n";
    $table_rows .= "</tr>\n";
}

$tpl =~ s/<!--TableStart-->.*?<!--TableEnd-->/<!--TableStart-->\n$table_rows<!--TableEnd-->/s
    or warn "Table markers <!--TableStart-->/<!--TableEnd--> not found, table not updated\n";

#
# 4) Update the email block:
#    'The attributes that were not released to the service are:\n ... \n\n'
#
my $missing_block = "";
for my $attr (@attrs) {
    $missing_block .= " * <shibmlpifnot $attr>$attr</shibmlpifnot>\n";
}

$tpl =~ s/(The attributes that were not released to the service are:\s*\n)(.*?)(\n\s*\n)/
          $1 . $missing_block . $3/seg
    or warn "Mail 'The attributes that were not released...' block not found, email list not updated\n";

#
# 5) Update the miss= parameter in the tracking pixel
#    ...&miss=SOMETHING"
#
my $miss_param = join("", map { "<shibmlpifnot $_>-$_</shibmlpifnot>" } @attrs);
$tpl =~ s/(miss=)[^"]*/$1$miss_param/;

#
# 6) Backup current generated template (if any) and write new one
#
if (-f $dst_template) {
    my $backup = $dst_template . ".bak." . time;
    rename $dst_template, $backup or die "Cannot backup $dst_template to $backup: $!";
    print "Backup of dst template saved to $backup\n";
}

open(my $out, '>:encoding(UTF-8)', $dst_template) or die "Cannot write $dst_template: $!";
print $out $tpl;
close $out;

print "\n1) Generated template: $dst_template\n";
print "2) Required attributes: ", join(", ", @attrs), "\n";
print "3) Test: sudo shibd -t && sudo systemctl restart shibd.service\n";
