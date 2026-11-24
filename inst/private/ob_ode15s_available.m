function yes = ob_ode15s_available (require = false)
  % True when this Octave can run ode15s, whose __ode15__ backend needs
  % SUNDIALS IDA.  Some distribution builds omit it (Ubuntu 26.04's octave
  % 11.1.0, for one); with REQUIRE, raise ob_run:ode15sUnavailable there
  % instead of __ode15__'s unidentified error from deep inside ode15s.
  persistent available
  if (isempty (available))
    available = true;
    try
      features = __octave_config_info__ ("build_features");
      available = logical (features.SUNDIALS_IDA && features.SUNDIALS_NVECSERIAL);
    catch
      % Unknown configuration layout: let ode15s report for itself.
    end_try_catch
  endif
  yes = available;
  if (require && ! yes)
    error ("ob_run:ode15sUnavailable", ...
           ["ob_run: solver 'ode15s' needs SUNDIALS IDA, but this Octave %s was " ...
            "built without it (__octave_config_info__ (\"build_features\")." ...
            "SUNDIALS_IDA is false); use solver 'ode45' or 'rk4', or an Octave " ...
            "built with SUNDIALS such as the GNU Octave Windows installer"], OCTAVE_VERSION);
  endif
endfunction
