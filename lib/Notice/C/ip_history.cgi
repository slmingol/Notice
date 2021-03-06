#!/usr/bin/perl

use strict;
use DBI;
use Carp;
use vars qw/ $db $dbhostname $dbusername $dbpassword /;
use Notice::DB qw( $db $dbhostname $dbusername $dbpassword );
# NTS  I'm sure this is not the best way to do this
*db = \$Notice::DB::db;
*dbhostname = \$Notice::DB::dbhostname;
*dbusername = \$Notice::DB::dbusername;
*dbpassword = \$Notice::DB::dbpassword;

use Notice::HTML ('html_header','html_footer','sidemenu');
use Notice::Common;
use Notice::DB::user;
my $page = $0; $page=~s/^.*\///;
my $env_request_URI = $ENV{REQUEST_URI};
my $ud = Notice::Common::check_for_login($env_request_URI);
use Notice::DB::user;
my $find_them = new Notice::DB::user;
my %user_details;
$user_details{URI} = $ud;
$find_them->Notice::DB::user::user_details(\%user_details);

my $action = $page . '?ud=' . $ud;

print html_header($page,$ud);
print sidemenu($page,$ud);

use Notice::CGI_Lite;
my $cgi=new CGI_Lite;
my %form=$cgi->parse_form_data();

my($col_order,$type_options,$number_options,%return);
my($dbh)=DBI->connect("DBI:mysql:$db:$dbhostname",$dbusername,$dbpassword,{PrintError=>0});
if (!$dbh) { croak('Couldn\'t connect to database'); }

if($user_details{pe_level} > 5){
	my $span=7; # week
	my $where=0; #today
	if($form{span}=~m/^\d+$/){ $span = $form{span}; }
	if($form{where}=~m/^\d+$/){ $where = $form{where}; }
	my $ip_hist_title= 'IP changes';

print qq|
<table width="100%" border="0" cellspacing="0" cellpadding="0">
<tr valign="top">
    <td class="content" height="2">|;
my $html_table = qq(
<table class="ip">
	<caption><em>$ip_hist_title</em></caption>
      <tr>
        <th class="ip"><a href="$page?ud=$ud">Who</a></th>
        <th class="ip"><a href="$page?ud=$ud">What</a></th>
        <th class="ip"><a href="$page?ud=$ud">When</a></th>
      </tr>
);

print $html_table;

my(%ip_types,$stripe);
my $iphist_query  = "SELECT ih_id,pe_id,pe_fname,pe_lname,ih_what,ih_when from iphistory,people where ih_peid = pe_id";
   $iphist_query .= " and ih_when BETWEEN DATE_ADD(CURDATE(), INTERVAL -$span DAY) AND DATE_ADD(DATE_ADD(CURDATE(), INTERVAL $span DAY), INTERVAL -$where DAY) order by ih_when"; 
	my ($sth)=($dbh)->prepare($iphist_query);
        $sth->execute() or croak("Can't execute query: $iphist_query");
    while(my @data = $sth->fetchrow_array()){
     
        print  qq(
        <tr class="$stripe">
                <td><!-- $data[0] | $data[1] -->$data[2] $data[3]</td>
                <td>$data[4]</td>
                <td>$data[5]</td>
        </tr>
        );
	if($stripe eq 'stripe'){ $stripe = 'strip';}
        else{ $stripe = 'stripe';}
    }

print "</table></td><td>";
	$html_table=~s/$ip_hist_title/IP Blocks changes/;
print $html_table;
	$stripe='strip';
my $ipphist_query  = "select pp_id,pe_id,pe_fname,pe_lname,pp_what,pp_when from ipphistory,people where pp_peid = pe_id";
 $ipphist_query .= " and pp_when BETWEEN DATE_ADD(CURDATE(), INTERVAL -$span DAY) AND DATE_ADD(DATE_ADD(CURDATE(), INTERVAL $span DAY), INTERVAL -$where DAY) order by pp_when";
        my ($sth)=($dbh)->prepare($ipphist_query);
        $sth->execute() or croak("Can't execute query: $ipphist_query");
    while(my @data = $sth->fetchrow_array()){
        print  qq(
        <tr class="$stripe">
                <td><!-- $data[0] | $data[1] -->$data[2] $data[3]</td>
                <td>$data[4]</td>
                <td>$data[5]</td>
        </tr>
        );
	if($stripe eq 'stripe'){ $stripe = 'strip';}
        else{ $stripe = 'stripe';}
    }

	print qq(
	</table>
</td></tr></table>);

} # end of level check
else
{
	print "Check with a sysadmin if you want to view ip  activity";
}

print html_footer;
