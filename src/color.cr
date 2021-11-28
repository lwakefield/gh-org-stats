class Color
  def self.interpolate (
    a : Tuple(Int32, Int32, Int32),
    b : Tuple(Int32, Int32, Int32),
    x : Float64
  )
    r1, g1, b1 = a
    r2, g2, b2 = b

    {
      interpolate(r1, r2, x),
      interpolate(g1, g2, x),
      interpolate(b1, b2, x)
    }
  end

  def self.to_rgb_string (a)
    "rgb(#{a.join(", ")}"
  end

  private def self.interpolate (
    a : Int32,
    b : Int32,
    c : Float64
  )
    if b < a
      c = 1 - c
      a, b = b, a
    end

    (a + ((b - a) * c)).to_i32
  end
end
