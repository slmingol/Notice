package Notice;
use strict;
use base 'CGI::Application';

use Notice::DB;
#use CGI::Application::Plugin::ConfigAuto (qw/cfg/);
use CGI::Application::Plugin::AutoRunmode;
use CGI::Application::Plugin::DBH(qw/dbh_config dbh/);
use CGI::Application::Plugin::Session;
use CGI::Application::Plugin::Authentication;
use CGI::Application::Plugin::Redirect;
use CGI::Application::Plugin::DBIC::Schema qw/dbic_config schema resultset/;
#use CGI::Application::Plugin::DebugScreen;
use Digest::MD5 qw(md5_hex);

use CGI::Application::Plugin::Forward;
use CGI::Application::Plugin::TT;
use Data::Dumper;

our $VERSION = 3.01;

=head1 NAME

Notice - A MVC (DBIC,TT,CAS) CGI::Application Customer Resource and Account Manager inspired by C:A:Structured

=head1 SYNOPSIS

    A controller module for Notice.
    
    Imports DBIx::Class schema here for all subclasses generated by script/create_controller.pl

=head1 DESCRIPTION

A base class for Controllers in this app. Subclasses are found
in the Notice::C:: (keeping the C in MVC seperated from, e.g. Notice::DB.)

=head1 METHODS

=head2 SUBCLASSED METHODS

=head3 cgiapp_init

Initializes the Controller base class for app, configures DBIx::Class plugin,
sets an error mode and configures the TT template directory.

=cut

sub cgiapp_init {
  my $self = shift;
  my %CFG;
  if(-f 'config/config.pl'){
    use CGI::Application::Plugin::ConfigAuto (qw/cfg/);
    #$self->cfg_file('config/config.pl'); #only needed if ommited from Notice::Dispatch
    %CFG = $self->cfg;
  }elsif(-f '../config/config.pl'){
    use CGI::Application::Plugin::ConfigAuto (qw/cfg/);
    %CFG = $self->cfg;
  }elsif(-f '../../config/config.pl'){
    use CGI::Application::Plugin::ConfigAuto (qw/cfg/);
    %CFG = $self->cfg;
  }else{
    warn('Default config');
        
    $CFG{db_schema} = 'Notice::DB';
    $CFG{db_dsn} = "dbi:mysql:database=notice";
    $CFG{db_user} = "notice_adminuser";
    $CFG{db_pw} = "12345678-abcd-1234-a693-00188bba79ac";
    $CFG{tt2_dir} = "templates";
  }

  #my @template_paths = ($self->cfg("tt2_dir") );
  my @template_paths = ($CFG{'tt2_dir'});
  $self->tt_include_path( \@template_paths, './templates' );
  $self->tmpl_path(\@template_paths);

  #let CGI::Application::Plugin::DBIC::Schema know where and what the database is
  $self->dbic_config(
        {
            schema       => $CFG{'db_schema'},
            connect_info => [
                $CFG{'db_dsn'},
                $CFG{'db_user'},
                $CFG{'db_pw'}
                ]    # use same args as DBI connect
        }
  );


  # open database connection using CGI::Application::Plugin::DBH
  # this is used by session_config to get a handel on the DB.
  # It would be nice if we could just pull a handel from DBIx::Class

  $self->dbh_config(
    $CFG{'db_dsn'},    # "dbi:mysql:database=webapp",
    $CFG{'db_user'},   # "webadmin",
    $CFG{'db_pw'},   # ""
  );

  $self->session_config(
    CGI_SESSION_OPTIONS => [
      "driver:mysql;serializer:Storable;id:md5",
      $self->query, {Handle => $self->dbh},
    ],

   DEFAULT_EXPIRY => '+1h', # a good choice
#    COOKIE_PARAMS => {
#      -name => 'MYCGIAPPSID',
#      -expires => '+24h',
#      -path => '/',
#    },
  );

  # configure authentication parameters
  $self->authen->config(
    DRIVER => [ 'DBI',
      DBH         => $self->dbh,
      TABLE       => 'people',
      CONSTRAINTS => {
	'people.pe_email'      => '__CREDENTIAL_1__',
        'MD5:people.pe_passwd' => '__CREDENTIAL_2__'
      },
    ],

    STORE                => 'Session',
    LOGOUT_RUNMODE       => 'logout',
    LOGIN_RUNMODE        => 'login',
    POST_LOGIN_RUNMODE   => 'okay',
    RENDER_LOGIN         => \&my_login_form,
  );

  # define runmodes (pages) that require successful login:
  $self->authen->protected_runmodes('mustlogin');

    my $known_as = '';
    my $username = '';
    if($self->query){
        my ($self_url) =  ($self->query->self_url);
        unless($self_url=~s/.*\/index.cgi\/([^\/]*)\/?\?.*/$1/){ $self_url = 'main'; } #runmode
        eval{
         if( $self->authen->is_authenticated){ 
            $username = $self->authen->username; 
            $self->param(username => $username);
            if($self->session->param('ef_acid')){ 
                my $ef_acid = $self->session->param('ef_acid');
                warn "$username has an effected account ID of $ef_acid" if $self->query->param('debug')>=2;
                $self->param(ef_acid => $ef_acid);
            }
            if($self->session->param('ac_tree')){ 
                my $ac_tree = $self->session->param('ac_tree');
                $self->param(ac_tree => $ac_tree);
            }
            
            if($self->session->param('known_as')){
                $known_as = $self->session->param('known_as');
                $self->param(known_as => $known_as); 
            }
            if($self->session->param('menu')){
                my $menu = $self->session->param('menu');
                $self->param(menu => $menu);
            }
            if($self->session->param('menu_order')){
                my @menu_order = $self->session->param('menu_order');
                $self->param(menu_order => @menu_order);
            }
            if($self->session->param('pe_id')){
                my $pe_id = $self->session->param('pe_id');
                $self->param(pe_id => $pe_id);
            }
            
            # we /should/ have populated our params from the session... but lets check

            if($username && !$self->session->param('menu')){
                #warn "$username ($known_as) has no session menu.. so we look" if $self->query->param('debug')>=20;
                my $user_data = $self->resultset('People')->search({
                    'pe_email' => { '=', "$username"},
                   },{
                    columns => ['pe_id','pe_acid','pe_fname','pe_lname','pe_menu']
                });
                my ($pe_id,$ef_acid,$ac_tree,$pe_menu);
                while( my $ud = $user_data->next){
                    $pe_id = $ud->pe_id; #later, for the admin we will have to have effective_peid as we do with ef_acid
                    $ef_acid = $ud->pe_acid;
                    $pe_menu = $ud->pe_menu;
                    $self->session->param(menu => $pe_menu);
                    $self->param(ef_acid => $ef_acid);
                    $known_as = $ud->pe_fname . ' ' . $ud->pe_lname;
                    $self->param(known_as => $username);
                    $self->param(pe_id => $pe_id);
                    if($ef_acid=~m/^\d+$/){
                        $self->session->param(ef_acid => $ef_acid);
                    }else{
                        $self->session->param(ef_acid => 'Account not found');
                    }
                    $self->session->param(known_as => $known_as);
                }
                
                if($pe_id=~m/^\d+$/){
                    my $acrs = $self->resultset('Account')->search({
                        'ac_id' => { '=', "$ef_acid"},
                    },{});
                    while( my $ac = $acrs->next){
                        my $ac_tree = $ac->ac_tree;
                        $self->param(ac_tree => $ac_tree);
                        $self->session->param(ac_tree => $ac_tree);
                    }
                    $self->session->param(pe_id => $pe_id);

                    my $menu_class = 'navigation'; #change the css not the class!
                    my $menu_rs = $self->resultset('Menu')->search({
                        'pe_id' => { '=', $self->param('pe_id')},
                        },{
                        columns => ['menu','hidden',{ name => 'modules.mo_name AS name'} ],
                        join => 'modules',
                        order_by => {-asc =>['pref','mo_default_hierarchy','menu+0']}
                        });
                    my %menu; # this will be a list of this users menu items
                    my @menu_order; #and this will be the order that they want them displayed in
                    # NTS pull this from the database
                    my %modules = (
                    '3.1' => {name => 'Email', rm=> 'email' },
                    3 => {name => 'Domains', rm=> 'domains' },
                    8 => {name => 'Assets', rm=> 'assets' },
                    20 => {name => 'Bee Keeping', rm=> 'beekeeping' },
                    );
                    # NOTE we can add global default menu items here
                    #warn "menu search:" if $self->query->param('debug')>=20;
                    while( my $m = $menu_rs->next){
                        my $menu_name = $modules{$m->menu()}{'name'};
                        my $rm = $modules{$m->menu()}{'rm'};
                         my $message = keys %{ $m };
                        $message .= $self->param('message');
                        $self->param(message => $message);
                        push @menu_order, $m->menu;
                        my $hidden = $m->hidden;
                        $menu{$m->menu} = {hidden => $hidden, rm => $rm, name => $menu_name, class => "$menu_class"};
                    }
                    my $menu_dump = Dumper(\%menu);
                    $self->param(menu => \%menu);
                    $self->param(menu_order => \@menu_order);
                    $self->session->param(menu => \%menu);
                    $self->session->param(menu_order => \@menu_order);
                    $self->tt_params({menu_order => \@menu_order});
                    $self->tt_params({menu => \%menu});
                }else{
                    warn "$self->param('pe_id') is undef so we can't search for menu items";
                }
            }
                # NTS not sure the Runmodes /need/ to know the menu options - we should probably just 
                # pass that directly into $self->tt_params(menu => \%menu);
          }
        };
        my $runmode = $self_url;
        if($self->param('rm')){ $runmode = $self->param('rm'); }
        $self->tt_params({title => 'Notice CRaAM  ' . $runmode ." - $known_as AT ". $ENV{REMOTE_ADDR}});
    }else{
        $self->tt_params({title => 'Notice CRaAM -' . $known_as . ' ON '. $ENV{REMOTE_ADDR}});
    }
}

=head3 teardown

database handel disconnection

=cut


sub teardown {
  my $self = shift;
  $self->dbh->disconnect(); # close database connection
}

=head3 mustlogin

yes! they must

=cut

sub mustlogin : Runmode {
  my $self = shift;
  my $url = $self->query->url;
  return $self->redirect($url);
}

=head3 okay

if it is, then it is

=cut

sub okay : Runmode {
  my $self = shift;
  my $url = $self->query->url;
  my $dest = $self->query->param('destination') || 'main';

  if ($self->param('noTLS') && $url =~ /^https/) {
    $url =~ s/^https/http/;
  }
  return $self->redirect("$url/$dest");
}

=head3 login

if you can - we should move this into Notice::C::Login

=cut

sub login : Runmode {
  my $self   = shift;
  my $url = $self->query->url;

  my $user = $self->authen->username;
  if ($user) {
    my $dest = $self->query->param('destination') || 'main';
    $url=~s/\/login$//;
    return $self->redirect("$url/$dest");
    exit;
  } else {
    my $url = $self->query->self_url;
    # This should be an option pulled from the DB config table
    unless ($url =~ /^https/) {
      $url =~ s/^http/https/;
      return $self->redirect($url);
    }
    return $self->my_login_form;
  }
}

=head3 my_login_form

going to move this to Notice::C::Login.pm as soon as I can
(Or just drop it as I don't think we use it anymore,
but it shows that we are not locked into TT.)

=cut

sub my_login_form {
  my $self = shift;
  my $template = $self->load_tmpl('login_form.html');

  (undef, my $info) = split(/\//, $ENV{'PATH_INFO'});
  my $url = $self->query->url;

  my $destination = $self->query->param('destination');

  unless ($destination) {
    if ($info) {
      $destination = $info;
    } else {
      $destination = "main";
    }
  }

  my $message = 'Would you be so kind as to login using your details. Thank you';
  my $error = $self->authen->login_attempts;
  if($url!~m/cgi-bin\/index.cgi/){
        $url=~s/cgi-bin/cgi-bin\/index.cgi/;
  }
  if($url!~m/mustlogin/){
    $url .= '/mustlogin';
    $message = 'Please login';
  }elsif($url=~m/mustlogin\/mustlogin/){
    $message = 'Try again... or click <a href="/cgi-bin/index.cgi/lost">here</a> to recover your password';
    $url=~s/mustlogin\/mustlogin/mustlogin/g;
  }

  $template->param(MESSAGE => $message);
  $template->param(MYURL => $url);
  $template->param(ERROR => $error);
  $template->param(DESTINATION => $destination);
  return $template->output;
}

=head3 logout

and don't let the door hit you on the way out

=cut

sub logout : Runmode {
  my $self = shift;
  if ($self->authen->username) {
    $self->authen->logout;
    $self->session->delete;
  }
  $self->param(message => 'You are no longer logged in');
  return $self->redirect($self->query->url);
}

=head3 myerror

or yours?

=cut

sub myerror : ErrorRunmode {
  my $self = shift;
  my $error = shift;
  my $url = $self->query->self_url;
     my $result = "<h1>error</h1>";
    $result .= "<h2>$@</h2>$error";
    $result .= "<br />p.s. URL = $url";
    # probably don't want a template as that might be what is going wrong
  $self->tt_params({no_wrapper => 1});
  $self->tt_params({message => $result});
    warn "Notice has a 'myerror'";
    return $self->tt_process('error.tmpl');
}

1;

__END__

=head1 BUGS AND LIMITATIONS

Probably, and certainly better ways to do the same thing

Please report any bugs or feature requests to
C<bug-notice at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=notice>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 SUPPORT AND DOCUMENTATION

After installing, you can find documentation for this module with the
perldoc command.

    perldoc Notice

You could also look for information at:

    Notice@GitHub
        http://github.com/alexxroche/Notice

    RT, CPAN's request tracker
        http://rt.cpan.org/NoAuth/Bugs.html?Dist=Notice

    AnnoCPAN, Annotated CPAN documentation
        http://annocpan.org/dist/Notice

    CPAN Ratings
        http://cpanratings.perl.org/d/Notice

    Search CPAN
        http://search.cpan.org/dist/Notice/


=head1 SEE ALSO

L<CGI::Application>, 
L<CGI::Application::Plugin::DBIC::Schema>, 
L<DBIx::Class>, 
L<CGI::Application::Structured>, 
L<CGI::Application::Structured::Tools>

=head1 AUTHOR

Alexx Roche, C<alexx@cpan.org>

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Alexx Roche

This program is free software; you can redistribute it and/or modify it
under the following license: Eclipse Public License, Version 1.0
or the Artistic License.

See http://www.opensource.org/licenses/ for more information.

=cut

