def main
  i = 0
  while i < 10
    trace fib(10)
    i += 1
  end
end

def fact(n)
  if n > 1
    n * fact(n - 1)
  else
    1
  end
end

def fib(n) => Integer
  if n < 2
    1
  else
    fib(n - 1) + fib(n - 2)
  end
end
