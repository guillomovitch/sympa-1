# -*- indent-tabs-mode: nil; -*-
# vim:ft=perl:et:sw=4

# This file is part of Sympa, see top-level README.md file for details

package Sympa::Template;

use strict;
use warnings;
use CGI::Util;
use English qw(-no_match_vars);
use MIME::EncWords;
use Template;

use Sympa;
use Conf;
use Sympa::Constants;
use Sympa::HTMLDecorator;
use Sympa::Language;
use Sympa::ListOpt;
use Sympa::Tools::Text;

my $language = Sympa::Language->instance;

sub new {
    my $class   = shift;
    my $that    = shift;
    my %options = @_;

    $options{include_path} ||= [];

    bless {%options, context => $that} => $class;
}

sub qencode {
    my $string = shift;
    # We are not able to determine the name of header field, so assume
    # longest (maybe) one.
    return MIME::EncWords::encode_mimewords(
        Encode::decode('utf8', $string),
        Encoding => 'A',
        Charset  => Conf::lang2charset($language->get_lang),
        Field    => "message-id"
    );
}

# OBSOLETED.  This is kept only for backward compatibility.
# Old name: tt2::escape_url().
sub _escape_url {
    my $string = shift;

    $string =~ s/([\s+])/sprintf('%%%02x', ord $1)/eg;
    # Some MUAs aren't able to decode ``%40'' (escaped ``@'') in e-mail
    # address of mailto: URL, or take ``@'' in query component for a
    # delimiter to separate URL from the rest.
    my ($body, $query) = split(/\?/, $string, 2);
    if (defined $query) {
        $query =~ s/(\@)/sprintf('%%%02x', ord $1)/eg;
        $string = $body . '?' . $query;
    }

    return $string;
}

# OBSOLETED.  This is kept only for backward compatibility.
# Old name:: tt2::escape_xml().
sub _escape_xml {
    my $string = shift;

    $string =~ s/&/&amp;/g;
    $string =~ s/</&lt;/g;
    $string =~ s/>/&gt;/g;
    $string =~ s/\'/&apos;/g;
    $string =~ s/\"/&quot;/g;

    return $string;
}

# Old name: tt2::escape_quote().
sub _escape_quote {
    my $string = shift;

    $string =~ s/\'/\\\'/g;
    $string =~ s/\"/\\\"/g;

    return $string;
}

sub encode_utf8 {
    my $string = shift;

    ## Skip if already internally tagged utf8
    if (Encode::is_utf8($string)) {
        return Encode::encode_utf8($string);
    }

    return $string;

}

sub decode_utf8 {
    my $string = shift;

    ## Skip if already internally tagged utf8
    unless (Encode::is_utf8($string)) {
        ## Wrapped with eval to prevent Sympa process from dying
        ## FB_CROAK is used instead of FB_WARN to pass $string intact to
        ## succeeding processes it operation fails
        eval { $string = Encode::decode('utf8', $string, Encode::FB_CROAK); };
        $EVAL_ERROR = '';
    }

    return $string;

}

# We use different catalog/textdomains depending on the template that
# requests translations.
# help.tt2 and help_*.tt2 templates use domain "web_help".  Others use default
# domain "sympa".
sub _template2textdomain {
    my $template_name = shift;
    return ($template_name =~ /\Ahelp(?:_\w+)?[.]tt2\z/) ? 'web_help' : '';
}

sub maketext {
    my ($context, @arg) = @_;

    my $template_name = $context->stash->get('component')->{'name'};
    my $textdomain    = _template2textdomain($template_name);

    return sub {
        my $ret = $language->maketext($textdomain, $_[0], @arg);
        # <acronym> was deprecated: Use <abbr> instead.
        $ret =~ s/(<\/?)acronym\b/${1}abbr/g
            if $ret and $textdomain eq 'web_help';
        return $ret;
    };
}

sub locdatetime {
    my ($fmt, $arg) = @_;
    if ($arg !~
        /^(\d{4})\D(\d\d?)(?:\D(\d\d?)(?:\D(\d\d?)\D(\d\d?)(?:\D(\d\d?))?)?)?/
        ) {
        return sub { $language->gettext("(unknown date)"); };
    } else {
        my @arg =
            ($6 || 0, $5 || 0, $4 || 0, $3 || 1, $2 - 1, $1 - 1900, 0, 0, 0);
        return sub { $language->gettext_strftime($_[0], @arg); };
    }
}

sub wrap {
    my ($context, $init, $subs, $cols) = @_;
    $init = '' unless defined $init;
    $init = ' ' x $init if $init =~ /^\d+$/;
    $subs = '' unless defined $subs;
    $subs = ' ' x $subs if $subs =~ /^\d+$/;

    return sub {
        my $text = shift;
        my $nl   = $text =~ /\n$/;
        my $ret  = Sympa::Tools::Text::wrap_text($text, $init, $subs, $cols);
        $ret =~ s/\n$// unless $nl;
        $ret;
    };
}

sub _mailto {
    my ($context, $email, $query, $nodecode) = @_;

    return sub {
        my $text = shift;

        unless ($text =~ /\S/) {
            $text =
                $nodecode ? Sympa::Tools::Text::encode_html($email) : $email;
        }
        return sprintf '<a href="%s">%s</a>',
            Sympa::Tools::Text::encode_html(
            Sympa::Tools::Text::mailtourl(
                $email,
                decode_html => !$nodecode,
                query       => $query,
            )
            ),
            $text;
    };
}

sub _mailtourl {
    my ($context, $query) = @_;

    return sub {
        my $text = shift;

        return Sympa::Tools::Text::mailtourl($text, query => $query);
    };
}

sub _obfuscate {
    my ($context, $mode) = @_;

    return sub {shift}
        unless grep { $mode eq $_ } qw(at javascript);

    return sub {
        my $text = shift;
        Sympa::HTMLDecorator->instance->decorate($text, email => $mode);
    };
}

sub _optdesc_func {
    my $self    = shift;
    my $type    = shift;
    my $withval = shift;

    my $that = $self->{context};
    my $encode_html = ($self->{subdir} && $self->{subdir} eq 'web_tt2');

    return sub {
        my $x = shift;
        return undef unless defined $x;
        return undef unless $x =~ /\S/;
        $x =~ s/^\s+//;
        $x =~ s/\s+$//;
        my $title = Sympa::ListOpt::get_option_description($that, $x, $type,
            $withval);
        $encode_html ? Sympa::Tools::Text::encode_html($title) : $title;
    };
}

sub _url_func {
    my $self   = shift;
    my $is_abs = shift;
    my $data   = shift;
    my %options;
    @options{qw(paths query fragment)} = @_;

    # Flatten nested path components.
    if ($options{paths} and @{$options{paths}}) {
        $options{paths} =
            [map { ref $_ eq 'ARRAY' ? @$_ : ($_) } @{$options{paths}}];
    }

    @options{qw(authority decode_html nomenu)} = (
        ($is_abs ? 'default' : 'omit'),
        ($self->{subdir} && $self->{subdir} eq 'web_tt2'),
        ($self->{subdir} && $self->{subdir} eq 'web_tt2' && $data->{nomenu}),
    );

    my $that = $self->{context};
    my $robot_id =
          (ref $that eq 'Sympa::List') ? $that->{'domain'}
        : ($that and $that ne '*') ? $that
        :                            '*';

    return sub {
        my $action = shift;

        my %nomenu;
        if ($action and $action =~ m{\Anomenu/(.*)\z}) {
            $action = $1;
            %nomenu = (nomenu => 1);
        }
        my $url = Sympa::get_url($robot_id, $action, %options, %nomenu);
        $options{decode_html} ? Sympa::Tools::Text::encode_html($url) : $url;
    };
}

sub parse {
    my $self       = shift;
    my $data       = shift;
    my $tpl_string = shift;
    my $output     = shift;
    my %options    = @_;

    my @include_path;
    if ($self->{plugins}) {
        push @include_path, @{$self->{plugins}->tt2Paths || []};
    }
    if (defined $self->{context}) {
        push @include_path,
            @{Sympa::get_search_path($self->{context}, %$self) || []};
    }
    if (@{$self->{include_path} || []}) {
        push @include_path, @{$self->{include_path}};
    }

    my $config = {
        ABSOLUTE => ($self->{allow_absolute} ? 1 : 0),
        INCLUDE_PATH => [@include_path],
        PLUGIN_BASE  => 'Sympa::Template::Plugin',
        # PRE_CHOMP  => 1,
        UNICODE => 0,    # Prevent BOM auto-detection

        FILTERS => {
            unescape => \&CGI::Util::unescape,
            l        => [\&maketext, 1],
            loc      => [\&maketext, 1],
            helploc  => [\&maketext, 1],
            locdt    => [\&locdatetime, 1],
            wrap      => [\&wrap,       1],
            mailto    => [\&_mailto,    1],
            mailtourl => [\&_mailtourl, 1],
            obfuscate => [\&_obfuscate, 1],
            optdesc => [sub { shift; $self->_optdesc_func(@_) }, 1],
            qencode      => [\&qencode,       0],
            escape_xml   => [\&_escape_xml,   0],
            escape_url   => [\&_escape_url,   0],
            escape_quote => [\&_escape_quote, 0],
            decode_utf8  => [\&decode_utf8,   0],
            encode_utf8  => [\&encode_utf8,   0],
            url_abs => [sub { shift; $self->_url_func(1, $data, @_) }, 1],
            url_rel => [sub { shift; $self->_url_func(0, $data, @_) }, 1],
            canonic_email => \&Sympa::Tools::Text::canonic_email,
        }
    };

    #unless ($options->{'is_not_template'}) {
    #    $config->{'INCLUDE_PATH'} = $self->{include_path};
    #}

    # An array can be used as a template (instead of a filename)
    if (ref $tpl_string eq 'ARRAY') {
        $tpl_string = \join('', @$tpl_string);
    }
    # body is separated by an empty line.
    if ($options{'has_header'}) {
        if (ref $tpl_string) {
            $tpl_string = \("\n" . $$tpl_string);
        } else {
            $tpl_string = \"\n[% PROCESS $tpl_string %]";
        }
    }

    my $tt2 = Template->new($config)
        or die "Template error: " . Template->error();

    # Set language if possible: Must be restored later
    $language->push_lang($data->{lang} || undef);

    unless ($tt2->process($tpl_string, $data, $output)) {
        $self->{last_error} = $tt2->error();

        $language->pop_lang;
        return undef;
    } else {
        delete $self->{last_error};

        $language->pop_lang;
        return 1;
    }
}

1;
__END__

=encoding utf-8

=head1 NAME

Sympa::Template - Template parser

=head1 SYNOPSIS

  use Sympa::Template;
  
  $template = Sympa::Template->new;
  $template->parse($data, $tpl_file, \$output);

=head1 DESCRIPTION

=head2 Methods

=over

=item new ( $that, [ property defaults ] )

I<Constructor>.
Creates new L<Sympa::Template> instance.

Parameters:

=over

=item $that

Context.  Site, Robot or List.

=item property defaults

Pairs to specify property defaults.

=back

=item parse ( $data, $tpl, $output, [ has_header => 1 ] )

I<Instance method>.
Parses template and outputs result.

Parameters:

=over

=item $data

A HASH ref containing the data.

=item $tpl

A string that contains the file name.
Or, scalarref or arrayref that contains the template.

=item $output

A file descriptor or a reference to scalar for the output.

=item has_header =E<gt> 0|1

If 1 is set, prepended header fields are assumed,
i.e. one newline will be inserted at beginning of output.

=item is_not_template =E<gt> 0|1

This option was obsoleted.

=back

Returns:

On success, returns C<1> and clears {last_error} property.
Otherwise returns C<undef> and sets {last_error} property.

=back

=head2 Properties

Instance of L<Sympa::Template> may have following attributes.

=over

=item {allow_absolute}

If set, absolute paths in C<INCLUDE> directive are allowed.

=item {include_path}

Reference to array containing additional template search paths.

=item {last_error}

I<Read only>.
Error occurred at the last execution of parse, or C<undef>.

=item {plugins}

TBD.

=item {subdir}, {lang}, {lang_only}

TBD.

=back

=head2 Filters

These custom filters are defined by L<Sympa::Template>.
See L<Template::Manual::Filters> about usage of filters.

=over

=item canonic_email

Canonicalize e-mail address.

This filter was added by Sympa 6.2.17.

=item decode_utf8

No longer used.

=item encode_utf8

No longer used.

=item escape_quote

Escape quotation marks.

=item escape_url

Escapes URL.

This was OBSOLETED.  Use L</"mailtourl"> instead.

=item escape_xml

OBSOLETED.  Use L<Template::Manual::Filters/"xml">.

=item helploc ( parameters )

=item l ( parameters )

=item loc ( parameters )

Translates text using catalog.
Placeholders (C<%1>, C<%2>, ...) are replaced by parameters.

=item locdt ( argument )

Generates formatted (i18n'ized) date/time.

=over

=item Filtered text

strftime() style format string.

=item argument

A string representing date/time:
"YYYY/MM", "YYYY/MM/DD", "YYYY/MM/DD/HH/MM" or "YYYY/MM/DD/HH/MM/SS".

=back

=item mailto ( email, [ {key =E<gt> val, ...}, [ nodecode ] ] )

Generates HTML fragment linking to C<mailto:> URL,
i.e. C<E<lt>a href="mailto:I<email>"E<gt>I<filtered text>E<lt>/aE<gt>>.

=over

=item Filtered text

Content of linking element.
If it does not contain nonspaces, e-mail address will be used.

=item email

E-mail address(es) to be linked.

=item {key =E<gt> val, ...}

Optional query.

=item nodecode

If true, assumes arguments are not encoded as HTML entities.
By default entities are decoded at first.

This option does I<not> affect filtered text.

=back

Note:
This filter was introduced by Sympa 6.2.14.

=item mailtourl ( [ {key = val, ...} ] )

Generates C<mailto:> URL.

=over

=item Filtered text

E-mail address(es).
Note that any characters must not be encoded as HTML entities.

=item {key = val, ...}

Optional query.
Note that any characters must not be encoded as HTML entities.

=back

Note:
This filter was introduced by Sympa 6.2.14.

=item obfuscate ( mode )

Obfuscates email addresses in the HTML text according to mode.

=over

=item Filtered text

HTML document or fragment.

=item mode

Obfuscation mode.  C<at> or C<javascript>.
Invalid mode will be silently ignored.

=back

Note:
This filter was introduced by Sympa 6.2.14.

=item optdesc ( type, withval )

Generates i18n'ed description of list parameter value.

As of Sympa 6.2.17, if it is called by the web templates
(in C<web_tt2> subdirectories),
special characters in result will be encoded.

=over

=item Filtered text

Parameter value.

=item type

Type of list parameter value:
Special types (See L<Sympa::ListDef/"field_type">)
or others (default).

=item withval

If parameter value is added to the description.  False by default.

=back

=item qencode

Encode string by MIME header encoding.
Despite its name, appropriate encoding scheme
(C<Q> or C<B>) will be chosen.

=item unescape

No longer used.

=item url_abs ( ... )

Same as L</"url_rel"> but gives absolute URI.

Note:
This filter was introduced by Sympa 6.2.15.

=item url_rel ( [ paths, [ query, [ fragment ] ] ] )

Gives relative URI for specified action.

If it is called by the web templates (in C<web_tt2> subdirectories),
HTML entities in the arguments will be decoded
and special characters in resulting URL will be encoded.

=over

=item Filtered text

Name of action.

=item paths

Array.  Additional path components.

=item query

Hash.  Optional query.

=item fragment

Scalar.  Optional fragment.

=back

Note:
This filter was introduced by Sympa 6.2.15.

=item wrap ( init, subs, cols )

Generates folded text.

=over

=item init

Indentation (or its length) of each paragraphm if any.

=item subs

Indentation (or its length) of other lines if any.

=item cols

Line width, defaults to 78.

=back

=back

B<Note>:

Calls of L</helploc>, L</loc> and L</locdt> in template files are
extracted during packaging process and are added to translation catalog.

=head2 Plugins

Plugins may be placed under F<LIBDIR/Sympa/Template/Plugin>.
See <https://www.sympa.org/manual/templates_plugins> about usage of
plugins.

=head1 SEE ALSO

L<Template::Manual>.

=head1 HISTORY

Sympa 4.2b.3 adopted template engine based on Template Toolkit.

Plugin feature was added on Sympa 6.2.

L<tt2> module was renamed to L<Sympa::Template> on Sympa 6.2.

=cut
