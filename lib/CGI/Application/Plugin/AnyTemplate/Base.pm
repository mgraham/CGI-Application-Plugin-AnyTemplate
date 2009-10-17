
package CGI::Application::Plugin::AnyTemplate::Base;

=head1 NAME

CGI::Application::Plugin::AnyTemplate::Base - Base class for templates

=head1 DESCRIPTION

This documentation is mainly for developers who want to write additional
Template drivers. For how to use the system, see the docs for
L<CGI::Application::Plugin::AnyTemplate>

=cut

use strict;
use Carp;
use Scalar::Util qw(weaken);

sub _new {
    my $proto = shift;
    my $class = ref $proto || $proto;

    my %args = @_;

    my $self = {};

    $self->{'driver_config'}     = delete $args{'driver_config'} || {};
    $self->{'native_config'}     = delete $args{'native_config'} || {};
    $self->{'include_paths'}     = delete $args{'include_paths'} || [];
    $self->{'filename'}          = delete $args{'filename'};
    $self->{'string_ref'}        = delete $args{'string_ref'};
    $self->{'callers_package'}   = delete $args{'callers_package'};
    $self->{'return_references'} = delete $args{'return_references'};
    $self->{'conf_name'}         = delete $args{'conf_name'};
    $self->{'webapp'}            = delete $args{'webapp'};

    $self->{'component_handler_class'} = delete $args{'component_handler_class'}
                                || 'CGI::Application::Plugin::AnyTemplate::ComponentHandler';

    bless $self, $class;

    weaken $self->{'webapp'};

    $self->initialize;

    return $self;
}

=head1 METHODS

=over 4

=item param

The C<param> method gets and sets values within the template.

    my $template = $self->template->load;

    my @param_names = $template->param();

    my $value = $template->param('name');

    $template->param('name' => 'value');
    $template->param(
        'name1' => 'value1',
        'name2' => 'value2'
    );

It is designed to behave similarly to the C<param> method in other modules like
C<CGI> and C<HTML::Template>.

=cut

sub param {
    my $self = shift;

    if (@_) {
        my $param;
        if (ref $_[0] eq 'HASH') {
            $param = shift;
        }
        elsif (@_ == 1) {
            return $self->{'param'}{$_[0]};
        }
        else {
            $param = { @_ };
        }
        $self->{'param'} ||= {};
        $self->{'param'}{$_} = $param->{$_} for keys %$param;
    }
    else {
        $self->{'param'} ||= {};
        return keys %{ $self->{'param'} };
    }
}

=item get_param_hash

Returns the template variables as a hash of names and values.

    my %params     = $template->get_param_hash;

In a scalar context, returns a reference to the hash used
internally to contain the values:

    my $params_ref = $template->get_param_hash;

=cut

sub get_param_hash {
    my $self = shift;
    $self->{'param'} ||= {};
    return %{ $self->{'param'} } if wantarray;
    return $self->{'param'};
}

=item clear_params

Clears the values stored in the template:

    $template->param(
        'name1' => 'value1',
        'name1' => 'value2'
    );
    $template->clear_params;
    $template->param(
        'name_foo' => 'value_bar',
    );

    # params are now:
        'name_foo' => 'value_bar',


=cut

sub clear_params {
    my $self = shift;
    $self->{'param'} = {};
}

=item output

Returns the template with all the values filled in.

    return $template->output();

You can also supply names and values to the template at this stage:

    return $template->output('name' => 'value', 'name2' => 'value2');

Before the template output is generated, the C<< template_pre_process >>
hook is called.  Any callbacks that you register to this hook will be
called before each template is processed.  Register a
C<template_pre_process> callback as follows:

    $self->add_callback('template_pre_process', \&my_tmpl_pre_process);

Pre-process callbacks will be passed a reference to the C<$template>
object, and can can modify the parameters passed into the template by
using the C<param> method:

    sub my_tmpl_pre_process {
        my ($self, $template) = @_;

        # Change the internal template parameters by reference
        my $params = $template->get_param_hash;

        foreach my $key (keys %$params) {
            $params{$key} = to_piglatin($params{$key});
        }

        # Can also set values using the param method
        $template->param('foo', 'bar');

    }


After the template output is generated, the C<template_post_process> hook is called.
You can register a C<template_post_process> callback as follows:

    $self->add_callback('template_post_process', \&my_tmpl_post_process);

Any callbacks that you register to this hook will be called after each
template is processed, and will be passed both a reference to the
template object and a reference to the output generated by the template.
This allows you to modify the output of the template:

    sub my_tmpl_post_process {
        my ($self, $template, $output_ref) = @_;

        $$output_ref =~ s/foo/bar/;
    }




When you call the C<output> method, any components embedded in the
template are run.  See C<EMBEDDED COMPONENTS>, below.

=cut

# calling forms:
#    $template->output;
#    $template->output('file.html', \%params);
#    $template->output(\%params)
#
#    $template->fill;
#    $template->fill('file.html', \%params);
#    $template->fill(\%params)

sub output {
    my $self = shift;

    $self->param(@_);

    my $webapp = $self->{'webapp'};

    if ($webapp and $webapp->can('call_hook')) {
        $webapp->call_hook('template_pre_process', $self);
    }

    my $output = $self->render_template;

    if ($webapp and $webapp->can('call_hook')) {
        my $output_param = $output;
        $output_param = \$output_param unless ref $output_param;
        $webapp->call_hook('template_post_process', $self, $output_param);
    }
    if ($self->{'return_references'}) {
        return ref $output ? $output : \$output;
    }
    else {
        return ref $output ? $$output : $output;
    }
}

=item filename

If the template was loaded from a file, the C<filename> method returns the template filename.

=cut

sub filename {
    my $self = shift;
    return $self->{'filename'};
}

=item string_ref

If the template was loaded from a string, the C<string_ref> method returns a reference to the string.

=cut

sub string_ref {
    my $self = shift;
    return $self->{'string_ref'};
}

=item object

Returns a reference to the underlying template driver, e.g. the
C<HTML::Template> object or the C<Template::Toolkit> object.

=back

=cut

sub object {
    my $self = shift;
    return $self->{'driver'};
}

=head1 DOCS FOR TEMPLATE MODULE DEVELOPERS

The following documentation is of interest primarly for developers who
wish to add support for a new type of Template system.

=head2 METHODS FOR DEVELOPERS

=over 4

=item initialize

This method is called by the controller at C<load> to create the
driver-specific subclass of C<CGI::Application::Plugin::AnyTemplate>

This is a virtual method and must be defined in the subclass.

The following paramters are passed to the driver and available as keys of the
driver's C<$self> object:

     'driver_config' => ...    # hashref of driver-specific config
     'native_config' => ...    # hashref of native template system specific config
     'include_paths' => ...    # listref of template include paths
     'filename'      => ...    # template filename
     'webapp'        => ...    # reference to the current CGI::Application $self

=cut

sub initialize {
    croak "Driver did not initialize its driver";
}


=item driver_config_keys

When it creates the driver object,
C<CGI::Application::Plugin::AnyTemplate> has to separate the
C<driver_config> from the C<native_config>.

C<driver_config_params> should return a list of parameters that are
specific to the driver_config and not the native template system
config.


For instance, the user can specify

    $self->template->config(
        HTMLTemplate => {
              embed_tag_name    => 'embed',
              global_vars       => 1,
              die_on_bad_params => 0,
              cache             => 1
        },
    );

The parameters C<global_vars>, C<die_on_bad_params>, and C<cache> are all
specific to L<HTML::Template>.  These are considered I<native> parameters.

But C<embed_tag_name> configures the
C<CGI::Application::Plugin::AnyTemplate::Driver::HTMLTemplate> subclass.  This
is considered a I<driver> parameter.

Therefore C<'embed_tag_name'> should be included in the list of
params returned by C<driver_config_params>.

Example C<driver_config_params>:

    sub driver_config_keys {
        'template_extension',
        'embed_tag_name'
    }

=cut

sub driver_config_keys {
    return;
}

=item default_driver_config

Should return a hash of default values for C<driver_config_params>.

For instance:

    sub default_driver_config {
        {
            template_extension => '.foo',
            embed_tag_name     => 'embed',
        };
    }


=cut

sub default_driver_config {
    return;
}

=item render_template

This method must be overriden in a subclass.  It has the responsibility
of filling the template in C<< $self->filename >> with the values in C<< $self->param >>
via the appropriate template system, and returning the output as either
a string or a reference to a string.

It also must manage embedding nested components.

=back

=cut

sub render_template {
    croak "render_template virtual method";
}

# Utility method for drivers to load their prerequsite modules

sub _require_prerequisite_modules {
    my ($class) = @_;

    my @missing_modules;

    foreach my $module ($class->required_modules) {
        eval "require $module";
        if ($@) {
            push @missing_modules, $module;
        }
        # $module->import;
    }
    if (@missing_modules) {
        foreach my $module (@missing_modules) {
            warn "$class: missing prerequisite module: $module\n";
        }
        die "Can't continue loading: $class\n";
    }
}


=head1 AUTHOR

Michael Graham, C<< <mag-perl@occamstoothbrush.com> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-cgi-application-plugin-anytemplate@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.  I will be notified, and then you'll automatically
be notified of progress on your bug as I make changes.

=head1 SEE ALSO

    CGI::Application::Plugin::AnyTemplate
    CGI::Application::Plugin::AnyTemplate::ComponentHandler
    CGI::Application::Plugin::AnyTemplate::Driver::HTMLTemplate
    CGI::Application::Plugin::AnyTemplate::Driver::HTMLTemplateExpr
    CGI::Application::Plugin::AnyTemplate::Driver::HTMLTemplatePluggable
    CGI::Application::Plugin::AnyTemplate::Driver::TemplateToolkit
    CGI::Application::Plugin::AnyTemplate::Driver::Petal

    CGI::Application

    Template::Toolkit
    HTML::Template

    HTML::Template::Pluggable
    HTML::Template::Plugin::Dot

    Petal

    CGI::Application::Plugin::TT

=head1 COPYRIGHT & LICENSE

Copyright 2005 Michael Graham, All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of CGI::Application::Plugin::AnyTemplate
