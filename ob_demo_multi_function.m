function [scaled, transposed, energy] = ob_demo_multi_function (input)
  % Ordinary Octave code with independently shaped output ports.
  scaled = 2 * input;
  transposed = input.';
  energy = sum (input(:).^2);
endfunction
