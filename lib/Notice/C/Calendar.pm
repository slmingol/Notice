package Notice::C::Calendar;

use strict;
require 5.006;
my %opt;
$opt{D}=0;
use lib 'lib';
# NOTE perl -cw was throwing errors ever since I moved from 5.6 to 5.14
# I tried all of the following, (and much more) but none helped.. then I realised that I needed to add the line above
# This was a non-fatal error, but it was masking other info, (so it worked but my usual test before loading did not.)
BEGIN {
#use attributes __PACKAGE__ => \&main, 'StartRunmode';
#use attributes __PACKAGE__ => \&__PACKAGE__::main, "StartRunmode";
#use attributes "Notice::C::Calendar" => \&Notice::C::Calendar::main, "StartRunmode";
}
#sub MODIFY_CODE_ATTRIBUTES{use Scalar::Util qw(refaddr);my($package,$subref,@attrs,%attrs)=@_;$attrs{refaddr $subref}=\@attrs;return;}
# sub MODIFY_CODE_ATTRIBUTES{return;} 

use base 'Notice';

use Data::Dumper;
use warnings;
#use warnings NONFATAL => 'all', FATAL => 'uninitialized';

# NTS pull this from the menu and modules table
my %submenu = ( 
   '1.2' => [
    ],
);

# pull from config?
my @categories = split(/,/, qq |,Anniversary,Birthday,Business,Calls,Clients,Competition,Customer,Favorites,Follow up,Gifts,Holidays,Ideas,Issues,Miscellaneous,Personal,Projects,Public Holiday,Status,Suppliers,Travel,Vacation|);


=head1 NAME

Notice::C::Calendar - Template controller subclass for Notice

=head1 ABSTRACT

This creates and displays calendar entries using RFC2445 to store details in Notice, or an external CalDAV server.

=head1 DESCRIPTION


=head1 METHODS

=head2 SUBCLASSED METHODS

=head3 setup

Override or add to configuration supplied by Notice::cgiapp_init.

=cut

sub setup {
    my ($self) = @_;
    $self->authen->protected_runmodes(':all');
    my $runmode;
    $runmode = ($self->query->self_url);
    $runmode =~s/\/$//;
    if($self->param('rm')){ 
        $runmode = $self->param('rm'); 
    }
    $runmode =~s/^.*\/(.+\/.+)$/$1/;
    if($self->param('id')){
        my $id = $self->param('id');
        if($self->param('extra1')){
            my $extra = $self->param('extra1');
            $runmode =~s/\/$extra[^\/]*//;
        }
        if($self->param('sid')){
            my $sid = $self->param('sid');
            $runmode =~s/\/$sid[^\/]*//;
        }
        $runmode =~s/\/$id[^\/]*$//;
    }
    if($runmode=~m/\/.*[=].*/){
        $runmode=~s/\/.*//;
    }else{
        $runmode=~s/.*\///;
    }
    $runmode=~s/.*\///;
}

=head2 RUN MODES

=head3 main

  * Let the use know which subsections of Notice::Email they have access to 

=cut

sub main : StartRunmode {
    my ($self) = @_;
    my ($message,$body,$cid,$uid,@calendars);
    $opt{D}=0;
    my $q = $self->query;
    my $surl;
       $surl = ($self->query->self_url);
    my %events;
    #find their pe_id (later we can search for group membership)
    my ($pe_id,$ac_id);
    my $username = '';
    $username = $self->authen->username;
    if($username && $username ne ''){
        $self->tt_params({ username => $username});
    }
    if($self->param('pe_id')=~m/^\d+$/){
      $pe_id = $self->param('pe_id');
    }elsif($self->session->param('pe_id')=~m/^\d+$/){
      $pe_id = $self->session->param('pe_id');
    }
    our $user_details;
    if($pe_id=~m/^\d+$/){
        $user_details = $self->resultset('People')->search({pe_id => $pe_id});
    }else{
        $user_details = $self->resultset('People')->search({pe_email => $username});
    }
    if($self->param('sid') && $self->param('sid')=~m/^([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})$/i){
        $uid = $1; # we are using a UUID for each ics
    }elsif($self->param('sid') && $self->param('sid')=~m/^(\d+)$/){
        $cid = $1; # calender id, i.e. sql auto_increment value
    }
    if($user_details && defined($opt{'pe_acid'}) && $opt{pe_acid}=~m/\d+/){
         while( my $ud = $user_details->next){
            if($ud->pe_acid){
                        $ac_id = $ud->pe_acid;
            }
         }
     }
        
    if($self->param('ef_acid')){ $ac_id = $self->param('ef_acid'); }
    elsif($self->param('ac_id')){ $ac_id = $self->param('ac_id'); }


    use Data::ICal;
    use Data::ICal::Entry::Event;
    use Date::Calc qw/Add_Delta_Days Decode_Date_US2/;
    use Data::UUID;
    use DateTime::TimeZone;
    my @tzs = DateTime::TimeZone->all_names();
    my $zt_html = '<select name="tz">';
    my $zt_is_set=0;
    my $tzid='Europe/London'; # again this default should be from the DB
    unless($q->param('tz')){ 
        # oooh this is painful - we should probably pull this from config or DB::config::timezone
        our $LocalTZ = DateTime::TimeZone->new( name => 'local' );
        our $timezone = $LocalTZ->name;
        unless($timezone){ $timezone = $tzid; } 
        $q->param('auto_tz' => $timezone);
        if($timezone ne $tzid){ $tzid = $timezone; }
    } 

=pod

    https://www.ietf.org/rfc/rfc2445.txt
    https://tools.ietf.org/html/rfc5545 https://www.ietf.org/rfc/rfc5545.txt
    dates are complicated. Oh they start out simple

     DTSTART:19970714T133000            ;Local datetime
     DTSTART:19970714T173000Z           ;UTC datetime
     DTSTART;TZID=US-Eastern:19970714T133000    ;Local time and time zone reference
     DTSTART;VALUE=DATE:20120524        ; local date (all day)

    then we have to code for:

     DURATION:19970101T180000Z/P15DT5H0M20S     ;represents 15 days, 5 hours and 20 seconds.
        or explicity 19970101T180000Z/19970102T070000Z

    and don't forget:
     RECUR (Recurrence i.e. weekly, monthly)

    and:
     RRULE:FREQ=YEARLY;COUNT=2;INTERVAL=4;BYDAY=1TH;BYMONTH=5    ;every four years for 8 years on the 1st monday of May

    and then:
     EXDATE (Exception Date/Times i.e. weekly meeting that does not happen in the first week of the month)
     EXDATE:19960402T010000Z,19960403T010000Z,19960404T010000Z

    and depricated from 2445->5545: (but we may have to deal with it)
     EXRULE:FREQ=WEEKLY;COUNT=4;INTERVAL=2;BYDAY=TU,TH
        ; Except every other week, on Tuesday and Thursday for 4 occurrences
        

    Not forgetting that depending on what sort of event it is, if it is a birthday or Anniversary then it is
     TRANSP:TRANSPARENT
    because it does not take up any time, but a birthday party would be
     TRANSP:OPAQUE

=cut

    TIMEZONE: foreach my $t (@tzs){
        next TIMEZONE unless $t=~m/\w+\/\w+/; # because that is what we need
        $zt_html .= '<option';
        # so if the user has a timezone we use it, if not they can set one and if they have not then we set it
        if( ( defined($self->param('pe_timezone')) && $t eq $self->param('pe_timezone') ) ||
            (!defined($self->param('pe_timezone')) && defined($q->param('tz')) && $t eq $q->param('tz')) ||
            (!defined($self->param('pe_timezone')) && !defined($q->param('tz')) && $t eq $q->param('auto_tz'))
          ){
            $tzid=$t;
            $zt_html .= ' selected="selected"';
            $zt_is_set=1;
        }
        $zt_html .='>';
        $zt_html .="$t</option>\n";
    }
    $zt_html .= '</select>';

    # for all your timestamp needs:
    use DateTime;
    my $zulu = DateTime->now( time_zone => 'UTC' )->strftime("%Y%m%dT%H%M%SZ");
    # N.B. order matters! # NOTE this should be populated from database config
    push (@calendars, { html => 'My work', value => "/$ac_id/$pe_id/work" } );
    push (@calendars, { html => 'My personal', value => "/$ac_id/$pe_id/personal" } );
    # N.B. the customer WILL be able to read your entries if they have a notice account!
    #push (@calendars, { html => 'Mr Smith (Good supply Inc)', value => "/12/14/supplier" } ); 

        #$events{soon} = "This<br />That<br />(99 more)";
    if ( $q->param('add_event') && $q->param('add_event') eq "Add" ) {


        # NTS we should check that they have not just pressed F5 and created a duplicate entry

        my $c = Data::ICal->new();
        my $vevent = Data::ICal::Entry::Event->new();
            
        my $summary='';
        my $desc='';
        my $cal='work';
        my $path='';
        if($q->param('cal')){ $cal = $q->param('cal'); $path = $cal;}
        else{ $path ='/cal/' . $ac_id . '/' . $pe_id . '/' . $cal; }
        unless($uid && $uid=~m/[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}/i){
            my $ug = new Data::UUID;
            $uid = $ug->create_str();
        }
        $vevent->add_properties( 
            uid => $uid,
            created => $zulu,
            'last-modified' => $zulu,
            dtstamp => $zulu,
            'x-notice-path' => $path
        );
        my %create_data = ( modified => \'NOW()' );   #this works
        my $end = $q->param('end_date');
        my ($ey,$em,$ed);
        my $description = $q->param('desc'); # because Data::ICal and mysql don't play well together
        $description =~s/\n/=0D=0A/g;
        if($q->param('summary')){ $vevent->add_properties(summary => $q->param('summary')); }
        else{ warn "we have NO summary, which is BAD!"; }
        if($q->param('where')){ $vevent->add_properties(location => $q->param('where')); }
        if($q->param('desc')){  $vevent->add_properties(description => $q->param('desc')); }
        my $dtstart = '';
        if($q->param('start_date')){
            $dtstart = sprintf( '%04d%02d%02d', Decode_Date_US2($q->param('start_date')));
            $create_data{'start'} = sprintf( '%04d-%02d-%02d', Decode_Date_US2($q->param('start_date')));
            if(defined($q->param('all_day'))){
                        # DTSTART;VALUE=DATE:20120524        ; local date (all day)
                $vevent->add_property( dtstart => [ $dtstart, { VALUE => 'DATE' } ] );
            }else{
               my $dtstart_time = '';
               if(defined($q->param('start_time')) && $q->param('start_time')=~m/\d{1,2}.?\d{1,2}/){
                  $dtstart_time = $q->param('start_time');
                  chomp($dtstart_time);
                  $dtstart_time =~s/h/:/i; # some write times as 16h15
                  # must be a better way to get hhmmss from '7:35 PM'
                  my $is_pm = $dtstart_time; $is_pm=~s/.* //;
                  $dtstart_time=~s/$is_pm$//;
                  my ($st_h,$st_m,$st_s) = split(/:/, $dtstart_time);
                  $st_m=~s/\s*$//;
                  if($is_pm=~m/pm/i){ $st_h+=12; }              # really?
                  if($st_h > 23 || $st_h <= 0){ $st_h= '00'; } # this might go wrong
                  elsif($st_h <= 9 ){ $st_h= '0' . $st_h; }
                  unless(defined($st_s) && $st_s=~m/^\d{2}$/){ $st_s = '00'; }
                  $create_data{'start'} .= " $st_h:$st_m:$st_s";
                  $dtstart_time = $st_h . $st_m . $st_s;
                  $dtstart_time =~s/\s*$//;
               }
               if(defined($tzid)){
                   if($tzid eq 'UTC' || $tzid eq 'Europe/London'){ # we should check if $tzid == UTC+0000
                        # DTSTART:19970714T173000Z           ;UTC datetime
                        $vevent->add_property( dtstart => "${dtstart}T${dtstart_time}Z");
                    }else{
                        # DTSTART;TZID=US-Eastern:19970714T133000    ;Local time and time zone reference
                        $dtstart_time=~s/^(\d)/T$1/;
                        $vevent->add_property( dtstart => [ "$dtstart$dtstart_time", { TZID => "$tzid" } ] );
                    }
               }else{
                    $vevent->add_property(
                         # DTSTART:19970714T133000            ;Local datetime
                            dtstart => "${dtstart}T$dtstart_time"
                    );
               }
            }
            # $vevent->add_properties(dtenart => sprintf( '%04d%02d%02d', Decode_Date_US2($q->param('start_date'))));
        }
        $create_data{'end'} = $end;         # ?
        if($q->param('busy')){ $vevent->add_properties(TRANSP => 'OPAQUE');}
        else{ $vevent->add_properties(TRANSP => 'TRANSPARENT');}
        if($q->param('cat')){ $vevent->add_properties(CATEGORIES => $q->param('cat'));}
        #if(($ey,$em,$ed) = split(/\//, $end)){ $vevent->add_properties(dtend => sprintf('%04d%02d%02d', Add_Delta_Days($ey,$em,$ed,$.)));}
        #if($q->param('end_date')){ $vevent->add_properties( dtend => sprintf('%04d%02d%02d', Decode_Date_US2($q->param('end_date')))); }

        my $dtend = sprintf( '%04d%02d%02d', Decode_Date_US2($q->param('end_date')));
        $create_data{'end'} = sprintf( '%04d-%02d-%02d', Decode_Date_US2($q->param('end_date')));
            if(defined($q->param('all_day'))){
                        # DTSTART;VALUE=DATE:20120524        ; local date (all day)
                if($dtend eq $dtstart){ $dtend+=1; } # which makes some sense
                $vevent->add_property( dtend => [ $dtend, { VALUE => 'DATE' } ] );
            }else{  
               my $dtend_time = '';
               if(defined($q->param('end_time')) && $q->param('end_time')=~m/\d{1,2}.?\d{1,2}/){
                  $dtend_time = $q->param('end_time');
                  chomp($dtend_time);
                  $dtend_time =~s/h/:/i; # some write times as 16h15
                  # must be a better way to get hhmmss from '7:35 PM'
                  my $is_pm = $dtend_time; $is_pm=~s/.* //;
                  $dtend_time=~s/$is_pm$//;
                  my ($en_h,$en_m,$en_s) = split(/:/, $dtend_time);
                  $en_m=~s/\s*$//;
                  if($is_pm=~m/pm/i){ $en_h+=12; }              # really?
                  if($en_h > 23 || $en_h <= 0){ $en_h= '00'; } # this might go wrong
                  elsif($en_h <= 9 ){ $en_h= '0' . $en_h; }
                  unless($en_s && $en_s=~m/^\d{2}$/){ $en_s = '00'; }
                  $create_data{'end'} .= " $en_h:$en_m:$en_s";
                  $dtend_time = $en_h . $en_m . $en_s;
                  $dtend_time =~s/\s*$//;
               }
               if(defined($tzid)){
                   if($tzid eq 'UTC' || $tzid eq 'Europe/London'){ # we should check if $tzid == UTC+0000
                        # DTSTART:19970714T173000Z           ;UTC datetime
                        $vevent->add_property( dtend => "${dtend}T${dtend_time}Z");
                    }else{
                        # DTSTART;TZID=US-Eastern:19970714T133000    ;Local time and time zone reference
                        $dtend_time=~s/^(\d)/T$1/;
                        $vevent->add_property( dtend => [ "$dtend$dtend_time", { TZID => $tzid } ] );
                    }
               }else{
                    $vevent->add_property(
                         # DTSTART:19970714T133000            ;Local datetime
                            dtend => "{$dtend}T$dtend_time"
                    );  
               }
            }

=pod

    X-NOTICE-PATH:/'cal'/[$acid|'contact']/$peid/work/
    DTSTART;TZID=Europe/Paris:20120522T160000
    DTEND;TZID=Europe/Paris:20120522T170000
    LOCATION:desktop-gloworm
    DESCRIPTION:Just a test desc\n
    TRANSP:OPAQUE
=cut

        $c->add_entry($vevent);

=pod

        $events{today} = '<pre>';
        $events{today} .= sprintf('%s', $c->as_string);
        $events{today} .= '</pre>';
        #$events{today} = "You just added an event";


 #DEBUG1

        ADD: foreach my $ak (keys %{ $q->{'param'} } ){
          if(1==0 && $q->param($ak) ne '' && $ak=~m/^\d+$/){
                my %create_data = ( asd_date => \'NOW()');
                $create_data{'asd_value'} = $q->param($ak);
                my $comment = $self->resultset('AssetData')->search( { asd_cid => $ak, asd_asid => $q->param('sid') });
                #$comment->update_or_create( \%create_data );
                $comment->create( \%create_data );
          }
          $events{soon} .= $ak . ":" . $q->param($ak) . "<br />\n";
        }
 #/DEBUG1

=cut

        foreach my $addk (keys %{ $q->{'param'} } ){
          # might be better to pull this from an array, but there must be a
          # better DBIx::Class way to know which collums we are looking for
          my $ak ='dsfgsdfg9843muc9uyt0n97ty0wn9ty98wevtuefgvb9c7r';
          if(
            $ak eq 'cid' ||
            $ak eq 'path' ||
            $ak eq 'uid'
           ){
            $create_data{"$ak"} = $q->param($ak);
           }elsif( $ak eq 'cal'){
            my (@this_path) = split('/', $q->param($ak));
            # should we be using pop here?
            # time  perl -e '$s="/th/is/iz/a/path.ics"; my (@this_path) = split("/", $s); print "uid: " . $this_path[@this_path-1] . "\n"; print join("/", @this_path) . "\n";'
            # time  perl -e '$s="/th/is/iz/a/path.ics"; my (@this_path) = split("/", $s); print "uid: " . (pop @this_path) . "\n"; print join("/", @this_path) . "\n";'
            $create_data{'uid'} = $this_path[@this_path-1];
            $create_data{'path'} = join('/', @this_path);
            $create_data{'path'} =~s/$create_data{'uid'}$//;
            $create_data{'uid'}=~s/\.ics\/?$//;      # clean up the path, as we know that this is an ics file
           }elsif( $ak eq 'user'){
            $create_data{'pe_id'} = $q->param($ak);
           }elsif( $ak eq 'owner'){
            $create_data{'added_by'} = $q->param($ak);
           }
        }
        $create_data{'cid'} = $cid;
        $create_data{'path'} = $path;
        $create_data{'ics'} = $uid;
        $create_data{'type'} = 'vevent';    # variable?
        $create_data{'version'} = '2.0';
        #$create_data{'data'} = sprintf('%s', $c->as_string); # check 
        $create_data{'data'} = $c->as_string; # check 
        $create_data{'peid'} = $pe_id;      # this might NOT be this users pe_id
        $create_data{'acid'} = $ac_id;      # ditto above
        $create_data{'added_by'} = $pe_id;  # this HAS to be this $user_details{pe_id} so that they can read it in the furture
        { # NOTE yes this is a very very dirty hack, why don't you fix it? (and check your work with perl -cw lib/Notice/C/Calendar.pm
        no warnings;
        $create_data{'created' => \'NOW()'}; # this might not work - remember to delete this item if we are doing an update!
        }
        #$create_data{'created' => \'NOW()'}; # this might not work - looks like it does not
        $create_data{'is_locked'} = 'N';

        if($opt{D}>=10){
            #use Data::Dumper::HTML qw(dumper_html);
            require Data::Dumper::HTML;
            
            $events{debug} .= qq{<div style="font-family: monospace">\n};
            $events{debug} .= "<br />DEBUG:\n" . Data::Dumper::HTML->dumper_html(\%create_data) . "<br /> END-DEBUG";
            $events{debug} .= qq{</div>\n};
        }

        my $rs = $self->resultset('Calendar')->search({
                peid => {'=', $pe_id},
                type => {'=', 'vevent'},
                cid => {'=', $cid},
                }, {})->first;
        if(defined($rs) && $q->param('cid') && $rs->cid == $q->param('cid')){
                 $create_data{cid} = $rs->cid;
                 # probably just need an update here
                 $rs = $self->resultset('Calendar')->update_or_create( \%create_data );
        }else{
            my $comment = $self->resultset('Calendar')->create( \%create_data );
            $comment->update;
            my $new_cid = $comment->id;
            #$warning = Dumper($comment);
            $self->tt_params( headmsg => qq |Event added! <a href='/cgi-bin/index.cgi/calendar/edit_event/$new_cid/'>Event added!</a>|);
        }
    } # end of "if add"

    $message = '';
    $body .=qq ||;

    my $cal_entries = $self->resultset('Calendar')->search(
        {
            added_by => {'=', $pe_id},
            type => {'=', 'vevent'},
            -or => [
              #-and => [
                start=> {'>', 'DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)'},
              # start=> {'<', 'DATE_SUB(CURRENT_DATE(), INTERVAL -6 DAY)'},
              #],
              #-and => [
                end  => {'<', 'DATE_SUB(CURRENT_DATE(), INTERVAL -6 DAY)'}
              # end  => {'>', 'DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)'}
              #],
            ]
                },{ order_by => {-asc =>['start','end+0'] } }
         );
    $events{yesterday} .= '<table class="event_show">';
    $events{today} .= '<table class="event_show">';
    $events{soon} .= '<table class="event_show">';
    $opt{row_count}{max} = 10; # again pull from config in the DB

    my %count; #N.B. do not use %opt to store these values!
    while(my $entry = $cal_entries->next){
        #$events{yesterday} = '<tr class="event_show"><th>Start</th><th>End</th><th>Summary</th></tr>';
        if(my $begin = $entry->start){
            my $finish = $entry->end;
            my $this_data = $entry->data;
            #$this_data=~s/\n/\\n/g;
            use Data::ICal;
            my $this_cal = Data::ICal->new(data => $this_data);
            if($this_cal){ #as long as it parses we still get an entry, so the user can edit blank entries
=pod

                foreach my $entry ( @{$this_cal->entries} ){
                    $opt{D} .= sprintf '<b>%s</b> - <a href="%s">%s</a> <i>%s</i><br>'."\n",
                    map { $entry->property($_)->[0]->value }
                    qw/ dtstart uid summary description /;
                }
=cut
                my ($fy,$fm,$fd) = $finish=~ /^([0-9]{4})-([0-9]{2})-([0-9]{2})/;
                my ($by,$bm,$bd) = $begin =~ /^([0-9]{4})-([0-9]{2})-([0-9]{2})/;
                my $DateTime_today = DateTime->now->truncate( to => 'day' );

              if( DateTime->compare( $DateTime_today, DateTime->new(year => $fy, month => $fm, day => ($fd+1), time_zone => "$tzid") ) >= 1 &&
                  DateTime->compare( $DateTime_today, DateTime->new(year => $by, month => $bm, day => $bd, time_zone => "$tzid") ) >= 1 
                ){
                    $count{row_count}{yesterday}++;
                    if( $count{row_count}{yesterday} >  $opt{row_count}{max} || ( $opt{row_count_yesterday} && ( 
                            $count{row_count}{yesterday} > $opt{row_count_yesterday} )
                    ))
                    {   
                        $count{yesterday_additional}++;
                    }else{
                        $events{yesterday} .= '<tr class="event_show"><td>' .$begin . "</td><td>" . $finish . "</td>";
                        $events{yesterday} .= '<td><a class="black" href="calendar/edit_entry/';
                        $events{yesterday} .= $entry->cid . '" title="';
                        $events{yesterday} .= @{$this_cal->entries}[0]->property('description')->[0]->value .'">';
                        $events{yesterday} .= @{$this_cal->entries}[0]->property('summary')->[0]->value ."</a></td></tr>";
                    }
              #} elsif( DateTime->compare(DateTime->today(), DateTime->new($begin) ) ){
              }elsif( DateTime->compare($DateTime_today, DateTime->new(year => $by, month => $bm, day => $bd, time_zone => "$tzid") ) == -1 ){
                $count{row_count}{soon}++;
                if($count{row_count}{soon} > $opt{row_count}{max} || ( $opt{row_count_soon} && ( $count{row_count}{soon} > $opt{row_count_soon} ) )){
                    $count{soon_additional}++;
                }else{
                    $events{soon} .= '<tr class="event_show"><td>' . $begin . "</td><td>" . $finish . "</td>";
                    $events{soon} .= '<td><a class="black" href="calendar/edit_entry/';
                    $events{soon} .= $entry->cid . '" title="';
                    $events{soon} .= @{$this_cal->entries}[0]->property('description')->[0]->value .'">';
                    $events{soon} .= @{$this_cal->entries}[0]->property('summary')->[0]->value ."</a></td></tr>";
                }
              }else{
                $count{row_count}{today}++;
                if($count{row_count}{today} > $opt{row_count}{max} || ( $opt{row_count_today} && ( $count{row_count}{today} > $opt{row_count_today} ) )){
                    $count{today_additional}++;
                }else{   
                  $events{today} .= '<tr class="event_show"><td>' . $begin . "</td><td>" . $finish . "</td>";
                  $events{today} .= '<td><a class="black" href="calendar/edit_entry/';
                  $events{today} .= $entry->cid . '" title="';
                  $events{today} .= @{$this_cal->entries}[0]->property('description')->[0]->value .'">';
                  if(@{$this_cal->entries}[0]->property('summary')){
                    $events{today} .= @{$this_cal->entries}[0]->property('summary')->[0]->value ."</a></td></tr>";
                  }else{
                    $events{today} .= 'EVENT </a></td></tr>';
                  }
                }
              }
            }
        }
    }
    if($count{yesterday_additional}){ 
        $events{yesterday} .= '<tr class="event_show"><td colspan="3">and ' . $count{yesterday_additional} . ' additional event';
        if($count{yesterday_additional} >= 2){ $events{yesterday} .= 's'; }
        $events{yesterday} .= '</td></tr>';
    }
    if($count{today_additional}){ 
        $events{today} .= '<tr class="event_show"><td colspan="3">and ' . $count{today_additional} . ' additional event';
        if($count{today_additional} >= 2){ $events{today} .= 's'; }
        $events{today} .= '</td></tr>';
    }
    if($count{soon_additional}){ 
        $events{soon} .= '<tr class="event_show"><td colspan="3">and ' . $count{soon_additional} . ' additional event';
        if($count{soon_additional} >= 2){ $events{soon} .= 's'; }
        $events{soon} .= '</td></tr>';
    }
    $events{yesterday} .= '</table>';
    $events{today} .= '</table>';
    $events{soon} .= '</table>';


    # create a hyperlink for each entry so that clickin on it will display it

    $self->tt_params({
    events => \%events,
	message => $message,
    zt_html => $zt_html,
    categories => \@categories,
    calendars => \@calendars,
    body    => $body
		  });
    return $self->tt_process();
}

=head2 RUN MODES

=head3 edit_entry

  * Let the use edit a calendar entry
  * Checks that they should have access to this entry

=cut

sub edit_entry : Runmode {
    my ($self) = @_;
    my ($message,$body,@calendars,$action_type);
    $action_type = 'New';
    my $q = $self->query;
    my $surl;
       $surl = ($self->query->self_url);
    my %events;
    #find their pe_id (later we can search for group membership)
    my ($pe_id,$ac_id,$uid);
    my $username = '';
    $username = $self->authen->username;
    if($username && $username ne ''){
        $self->tt_params({ username => $username});
    }
    if($self->param('pe_id')=~m/^\d+$/){
      $pe_id = $self->param('pe_id');
    }elsif($self->session->param('pe_id')=~m/^\d+$/){
      $pe_id = $self->session->param('pe_id');
    }
    # N.B. iCalendar has UID, Notice calls it ics for clarity
    if($q->param('ics') && $q->param('ics')=~m/\w+-\w+-\w+/){
        $uid = $q->param('ics');
    }
    my $cid = 0;
    if($q->param('cid') && $q->param('cid')=~m/^\d+$/){
        $cid = $q->param('cid');
    }elsif($self->param('id') && $self->param('id')=~m/^(\d+)$/){
        $cid = $1; # calender id, i.e. sql auto_increment value
    }elsif($self->param('sid') && $self->param('sid')=~m/^(\d+)$/){
        $cid = $1; # calender id, i.e. sql auto_increment value
    }

    our $user_details;
    if($pe_id=~m/^\d+$/){
        $user_details = $self->resultset('People')->search({pe_id => $pe_id});
    }else{
        $user_details = $self->resultset('People')->search({pe_email => $username});
    }
    if($user_details && defined($opt{'pe_acid'}) && $opt{pe_acid}=~m/\d+/){
         while( my $ud = $user_details->next){
            if($ud->pe_acid){
                        $ac_id = $ud->pe_acid;
            }
         }
     }

    if($self->param('ef_acid')){ $ac_id = $self->param('ef_acid'); }
    elsif($self->param('ac_id')){ $ac_id = $self->param('ac_id'); }

    use Data::ICal;
    use Data::ICal::Entry::Event;
    use Date::Calc qw/Add_Delta_Days Decode_Date_US2/;
    use Data::UUID;
    use DateTime::TimeZone;
    use DateTime;
    my $zulu = DateTime->now( time_zone => 'UTC' )->strftime("%Y%m%dT%H%M%SZ");
    
    my $tzid='Europe/London'; # again this default should be from the DB
    my $tz_is_set =0; #i.e. we are using the default
    if($q->param('tz')){
        $tzid = $q->param('tz');
        my $tz_is_set =1;
        #warn "652:TZ set from form $tzid";
    }elsif($q->param('auto_tz')){
        $tzid = $q->param('auto_tz');
        warn "655:auto TZ $tzid";
    }

    if ( $q->param('update_event') && $q->param('update_event') eq "Update" ) {
        # NTS we should let them know that this has been updated with a fading warning message, or something

        my $c = Data::ICal->new();
        my $vevent = Data::ICal::Entry::Event->new();
            
        my $summary='';
        $summary= $q->param('summary');
        my $desc='';
        $desc= $q->param('desc');
        my $cal='work';
        if($q->param('cal')){ $cal = $q->param('cal'); }
        $cal=~s#//#/#g;
        $vevent->add_properties( 
            uid => $uid,
            'last-modified' => $zulu,
            dtstamp => $zulu,
            'x-notice-path' => $cal
        );
        my %create_data = ( modified => \'NOW()' );   #this works
        my $end = $q->param('end_date');
        my ($ey,$em,$ed);
        my $description = $q->param('desc'); # because Data::ICal and mysql don't play well together
        $description =~s/\n/=0D=0A/g;
        if($q->param('summary')){ $vevent->add_properties(summary => $q->param('summary')); }
        if($q->param('where')){ $vevent->add_properties(location => $q->param('where')); }
        if($q->param('desc')){  $vevent->add_properties(description => $q->param('desc')); }
        my $dtstart = '';
        if($q->param('start_date')){
            $dtstart = sprintf( '%04d%02d%02d', Decode_Date_US2($q->param('start_date')));
            $create_data{'start'} = sprintf( '%04d-%02d-%02d', Decode_Date_US2($q->param('start_date')));
            if(defined($q->param('all_day'))){
                        # DTSTART;VALUE=DATE:20120524        ; local date (all day)
                $vevent->add_property( dtstart => [ $dtstart, { VALUE => 'DATE' } ] );
            }else{
               my $dtstart_time = '';
                # there has got to be a my $hh_mm_ss = parse_time($q->param('start_time'));
               if(defined($q->param('start_time')) && $q->param('start_time')=~m/\d{1,2}.?\d{1,2}/){
                  $dtstart_time = $q->param('start_time');
                  chomp($dtstart_time);
                  $dtstart_time =~s/h/:/i; # some write times as 16h15
                  # must be a better way to get hhmmss from '7:35 PM'
                  my $is_pm = $dtstart_time; $is_pm=~s/.* //;
                  if($is_pm && $is_pm ne $dtstart_time){ $dtstart_time=~s/$is_pm$//; }
                  my ($st_h,$st_m,$st_s) = split(/:/, $dtstart_time);
                  if( (defined $st_s && $st_s=~m/\d/ ) && (!defined($st_m) || $st_m eq '') ){
                        $st_m = $st_s; $st_s = '00';
                  }
                  $st_m=~s/\s*$//;
                  if($is_pm=~m/pm/i){ $st_h+=12; }              # really?
                  if($st_h > 23 || $st_h <= 0){ $st_h= '00'; } # this might go wrong
                  elsif($st_h <= 9 ){ $st_h= '0' . $st_h; }
                  unless(defined($st_s) && $st_s=~m/^\d{2}$/){ $st_s = '00'; }
                  $create_data{'start'} .= " $st_h:$st_m:$st_s";
                  $dtstart_time = $st_h . $st_m . $st_s;
                  $dtstart_time =~s/\s*$//;
               }
               if(defined($tzid)){
                   if($tzid eq 'UTC' || $tzid eq 'Europe/London'){ # we should check if $tzid == UTC+0000
                        # DTSTART:19970714T173000Z           ;UTC datetime
                        $vevent->add_property( dtstart => "${dtstart}T${dtstart_time}Z");
                    }else{
                        # DTSTART;TZID=US-Eastern:19970714T133000    ;Local time and time zone reference
                        $dtstart_time=~s/^(\d)/T$1/;
                        $vevent->add_property( dtstart => [ "$dtstart$dtstart_time", { TZID => "$tzid" } ] );
                    }
               }else{
                    warn "CHANGING $tzid to UTC!!";
                    $tzid = 'Europe/London'; #UTC
                    $vevent->add_property(
                         # DTSTART:19970714T133000            ;Local datetime
                            dtstart => "${dtstart}T$dtstart_time"
                    );
               }
            }
            # $vevent->add_properties(dtenart => sprintf( '%04d%02d%02d', Decode_Date_US2($q->param('start_date'))));
        }
        $create_data{'end'} = $end;         # ?
        if($q->param('busy')){ $vevent->add_properties(TRANSP => 'OPAQUE');}
        else{ $vevent->add_properties(TRANSP => 'TRANSPARENT');}
        if($q->param('cat')){ $vevent->add_properties(CATEGORIES => $q->param('cat'));} #why is this not working?

        my $dtend = sprintf( '%04d%02d%02d', Decode_Date_US2($q->param('end_date')));
        $create_data{'end'} = sprintf( '%04d-%02d-%02d', Decode_Date_US2($q->param('end_date')));
            if(defined($q->param('all_day'))){
                        # DTSTART;VALUE=DATE:20120524        ; local date (all day)
                if($dtend eq $dtstart){ $dtend+=1; } # which makes some sense
                $vevent->add_property( dtend => [ $dtend, { VALUE => 'DATE' } ] );
            }else{  
               my $dtend_time = '';
               if(defined($q->param('end_time')) && $q->param('end_time')=~m/\d{1,2}.?\d{1,2}/){
                  $dtend_time = $q->param('end_time');
                  chomp($dtend_time);
                  $dtend_time =~s/h/:/i; # some write times as 16h15
                  # must be a better way to get hhmmss from '7:35 PM'
                  my $is_pm = $dtend_time; $is_pm=~s/.* //;
                  if($is_pm && $is_pm ne $dtend_time){ $dtend_time=~s/$is_pm$//; }
                  my ($en_h,$en_m,$en_s) = split(/:/, $dtend_time);
                  if( (defined $en_s && $en_s=~m/\d/ ) && (!defined($en_m) || $en_m eq '') ){
                        $en_m = $en_s; $en_s = '00';
                  }
                  $en_m=~s/\s*$//;
                  if($is_pm=~m/pm/i){ $en_h+=12; }              # really?
                  if($en_h > 23 || $en_h <= 0){ $en_h= '00'; } # this might go wrong
                  elsif($en_h <= 9 ){ $en_h= '0' . $en_h; }
                  unless($en_s && $en_s=~m/^\d{2}$/){ $en_s = '00'; }
                  $create_data{'end'} .= " $en_h:$en_m:$en_s";
                  $dtend_time = $en_h . $en_m . $en_s;
                  $dtend_time =~s/\s*$//;
               }
               if(defined($tzid)){
                   if($tzid eq 'UTC' || $tzid eq 'Europe/London'){ # we should check if $tzid == UTC+0000
                        # DTSTART:19970714T173000Z           ;UTC datetime
                        $vevent->add_property( dtend => "${dtend}T${dtend_time}Z");
                    }else{
                        # DTSTART;TZID=US-Eastern:19970714T133000    ;Local time and time zone reference
                        $dtend_time=~s/^(\d)/T$1/;
                        $vevent->add_property( dtend => [ "$dtend$dtend_time", { TZID => $tzid } ] );
                    }
               }else{
                    $vevent->add_property(
                         # DTSTART:19970714T133000            ;Local datetime
                            dtend => "{$dtend}T$dtend_time"
                    );  
               }
            }
        my $rs = $self->resultset('Calendar')->search({ type => 'vevent', cid => $cid })->first;
        if(defined($rs) && $q->param('cid') && $rs->ics eq $q->param('ics')){

        our $created_datetime = $zulu;
        eval {
            $created_datetime = $rs->data;
            $created_datetime =~s/.*CREATED:(\d+T\d|).*/$1/s;
            unless($created_datetime=~m/^\d+T\d+Z$/){ $created_datetime = $zulu; }
            # we could create a new calendat object and extract the datetime 
            # from it using $vevent... or just use a regexp, (and this _is_perl)
            #
            # update: that IS what we should do, so that we can compare each of the data lines and if none have changed it reduces the update
            # If they have then we add the new data AND add all of the data that has NOT changed, (or we lose it!)
            my $this_data = $rs->data; #the old data from the database
            use Data::ICal;
            my $this_cal = Data::ICal->new(data => $this_data); #old data
            if($this_cal){ #as long as it parses we still get an entry, so the user can edit blank entries
                # should be a foreach in here
                foreach my $erow (keys %{ @{$this_cal->entries}[0]->properties }){
                    unless($q->param($erow)){
                        warn $erow . " was " . @{$this_cal->entries}[0]->property("$erow")->[0]->value if $opt{D}>=5;
                    }
                }
                 #warn "setting categories to:" . @{$this_cal->entries}[0]->property('categories')->[0]->value;
                 my $this_cat = @{$this_cal->entries}[0]->property('categories')->[0]->value;
                 unless($q->param('cat')){ $vevent->add_properties(CATEGORIES => $this_cat);}
            }
        };
        if($@){ warn $@; }
        
        $vevent->add_property( created => $created_datetime ); 
        $c->add_entry($vevent);

        $create_data{'cid'} = $cid;
        $create_data{'path'} = $cal;
        $create_data{'ics'} = $uid;
        $create_data{'version'} = '2.0';
        $create_data{'data'} = $c->as_string;
        $create_data{'added_by'} = $pe_id;

            $create_data{cid} = $rs->cid;
            $rs = $self->resultset('Calendar')->update_or_create( \%create_data );
            my $new_cid = $rs->id;
            $self->tt_params( headmsg => qq |Event updated! <a href='/cgi-bin/index.cgi/calendar/edit_event/$new_cid/'>Event updated!</a>|);
        }else{
            $self->tt_params({ warning => qq |Event failed to update!|});
        }
    } # end of "if update"

    $message = '';
    $body .=qq ||;

    #my $cal_entries = $self->resultset('Calendar')->search(

    my @event_rs = $self->resultset('Calendar')->search({
            added_by => $pe_id,
            type => 'vevent',
            -or => [
                cid => $cid,
                ics => $uid,
            ],   
                },{ row => 1}
         )->first;

    use Data::ICal;
    use Data::Dumper;
    my $this_data = $event_rs[0]->{_column_data}{data};
    $events{data} = $this_data if $opt{D}>=1;
    
    #$message = Dumper(\$event_rs);
    my $c = Data::ICal->new(data => $this_data);
    if($this_data && $c->entries){ #as long as it parses we still get an entry, so the user can edit blank entries
        $events{ics} = $event_rs[0]->{_column_data}{ics};
        $events{cid} = $event_rs[0]->{_column_data}{cid};
        foreach my $entry ( @{$c->entries} ){
            #$events{title} = $entry->property('summary')->[0]->value;
            my @data =  keys %{ $entry->properties };
            foreach my $thing ( @data ){
                $events{$thing} = $entry->property("$thing")->[0]->value;
                # extract the Time Zone
                if($thing eq 'dtstart' || $thing eq 'dtend'){
                    unless($tzid && $tzid=~m/\w+\/?\w*/ && $tz_is_set){ 
                        #my $test_tz = Dumper($entry->property("$thing")->[0]->parameters );
                        if( defined $entry->property("$thing")->[0]->parameters) {
                            $tzid = $entry->property("$thing")->[0]->parameters->{'TZID'};
                            $tz_is_set =1; #rather than the default;
                        }
                    }
                }
                #warn "$thing = $events{$thing}";
            }
        }
        $events{data} = Dumper(\%events) if $opt{D}>=1;
        $body .=  @{$c->entries}[0]->property('description')->[0]->value; # this can't be the right way.
        $action_type = 'edit';
    }elsif($cid > 0 || ($uid && $uid=~m/.*/) ){
        # probably someone fishing 
        $action_type = 'New';
        $self->tt_params({ warning => 'You do know that we are watching you - this has been reported'});
    }

    use DateTime::TimeZone;
    my @tzs = DateTime::TimeZone->all_names();
    my $zt_html = '<select name="tz">';
    TIMEZONE: foreach my $t (@tzs){
        next TIMEZONE unless $t=~m/\w+\/\w+/; # because that is what we need
        $zt_html .= '<option';
        # so if the user has a timezone we use it, if not they can set one and if they have not then we set it
        {
        no warnings;
        if( ( defined($tzid) && "$t" eq "$tzid" ) ||
            ( defined($self->param('pe_timezone')) && $t eq $self->param('pe_timezone') ) ||
            ( defined($q->param('tz')) && $t eq $q->param('tz')) ||
            ( defined($q->param('auto_tz')) && $t eq $q->param('auto_tz'))
          ){
            $zt_html .= ' selected="selected"';
          }
        }
        $zt_html .='>';
        $zt_html .="$t</option>\n";
    }
    $zt_html .= '</select>';


    $self->tt_params({
    e => \%events,
    event_action => $action_type,
    message => $message,
    zt_html => $zt_html,
    categories => \@categories,
    body    => $body
          });
    return $self->tt_process();

}

=head3 day

  * view all of the calendar entries for a particular day
  * defaults to today

=cut

sub day : Runmode {
    my ($self) = @_;
    my ($pe_id,$cid,$uid,@events);
    my $q = $self->query;
    my $surl;
       $surl = ($self->query->self_url);
    my $id = $self->param('id');
    $pe_id = $self->param('pe_id');
    use DateTime;
    my $when = $id ? $id : DateTime->now( time_zone => 'UTC' )->strftime("%Y-%m-%d");
    $when=~s/\D//g;
    $when=~s/(\d+)(\d{2})(\d{2})$/$1-$2-$3/;

  eval {
    @events = $self->resultset('Calendar')->search({
        added_by => {'=', $pe_id},
        type => {'=', 'vevent'},
        -or => [
                start=> {'like', "$when\%"},
                end  => {'like', "$when\%"},
        ]
        },{ order_by => {-asc =>['start','end+0'] }
    });
  };
  if($@){ warn $@; }
    my @hours = (0..23);
    $self->tt_params({
        when => $when,
        hours => \@hours,
        events => \@events,
       ## categories => \@categories,
    });
    return $self->tt_process('Notice/C/Calendar/day.tmpl');

}

=head3 year

  * view all the calendar entries for a particular year
  * defaults to this year

=cut

sub year : Runmode {
    my ($self) = @_;
    my ($pe_id,$cid,$uid,@events);
    my $q = $self->query;
    my $surl;
       $surl = ($self->query->self_url);
    my $id = $self->param('id');
    $pe_id = $self->param('pe_id');
    use DateTime;
    my $when = $id ? $id : DateTime->now( time_zone => 'UTC' )->strftime("%Y");
    $when=~s/\D//g;

  eval {
    @events = $self->resultset('Calendar')->search({
        added_by => {'=', $pe_id},
        type => {'=', 'vevent'},
        -or => [
                start=> {'like', "$when\%"},
                end  => {'like', "$when\%"},
        ]
        },{ order_by => {-asc =>['start','end+0'] }
    });
  };
  if($@){ warn $@; }
    $self->tt_params({
        when => "$when",
        events => \@events,
        wrapper => 1,
    });
    return $self->tt_process('Notice/C/Calendar/sw_year.tmpl');

}

=head3 new_event

  * a new event

=cut

sub new_event : Runmode {
    my ($self) = @_;
    my ($pe_id,$cid,$uid,@events);
    my $q = $self->query;
    my $surl;
       $surl = ($self->query->self_url);
    my $id = $self->param('id');
    $pe_id = $self->param('pe_id');
    use DateTime;
    my $when = $id ? $id : DateTime->now( time_zone => 'UTC' )->strftime("%Y");
    $when=~s/\D//g;

  eval {
    @events = $self->resultset('Calendar')->search({
        added_by => {'=', $pe_id},
        type => {'=', 'vevent'},
        -or => [
                start=> {'like', "$when\%"},
                end  => {'like', "$when\%"},
        ]
        },{ order_by => {-asc =>['start','end+0'] }
    });
  };
  if($@){ warn $@; }
    $self->tt_params({
        when => "$when",
        events => \@events,
        wrapper => 1,
    });
    return $self->tt_process();

}


=head3 add_todo

  * a new To-do

=cut

sub add_todo : Runmode {
    my ($self) = @_;
    my ($pe_id,$cid,$uid,@events);
    my $q = $self->query;
    my $surl;
       $surl = ($self->query->self_url);
    my $id = $self->param('id');
    $pe_id = $self->param('pe_id');
    use DateTime;
    my $when = $id ? $id : DateTime->now( time_zone => 'UTC' )->strftime("%Y");
    $when=~s/\D//g;

  eval {
    @events = $self->resultset('Calendar')->search({
        added_by => {'=', $pe_id},
        type => {'=', 'vevent'},
        -or => [
                start=> {'like', "$when\%"},
                end  => {'like', "$when\%"},
        ]
        },{ order_by => {-asc =>['start','end+0'] }
    });
  };
  if($@){ warn $@; }
    $self->tt_params({
        when => "$when",
        events => \@events,
        wrapper => 1,
    });
    return $self->tt_process();

}


1;

__END__

=head1 BUGS AND LIMITATIONS

There are no known problems with this module.
(Other than it has not been writen yet.)
Please fix any bugs or add any features you need. 
You can report them through GitHub or CPAN.

=head1 SEE ALSO

L<Notice>, L<CGI::Application>

=head1 SUPPORT AND DOCUMENTATION

You could look for information at:

    Notice@GitHub
        http://github.com/alexxroche/Notice

=head1 AUTHOR

Alexx Roche, C<alexx@cpan.org>

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2012 Alexx Roche

This program is free software; you can redistribute it and/or modify it
under the following license: Eclipse Public License, Version 1.0
or the Artistic License, Version 2.0

See http://www.opensource.org/licenses/ for more information.

=cut


