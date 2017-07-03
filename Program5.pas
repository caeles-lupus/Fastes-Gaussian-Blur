{
»сточник алгоритма: http://blog.ivank.net/fastest-gaussian-blur.html
»сточник кода на C#: https://github.com/mdymel/superfastblur/blob/master/SuperfastBlur/GaussianBlur.cs
}
uses graphabc;

function inc_(n:integer):integer;
begin
n+=1;
result := n;
end;

type
  Stopwatch = System.Diagnostics.Stopwatch;

  Bitmap = System.Drawing.Bitmap;
  BitmapData = system.Drawing.Imaging.BitmapData;
  Rectangle = System.Drawing.Rectangle;
  ImageLockMode = system.Drawing.Imaging.ImageLockMode;
  PixelFormat = System.Drawing.Imaging.PixelFormat;
  IntPtr = system.IntPtr;
  TByteRgb = array[,,] of byte;
  Marshal = system.Runtime.InteropServices.Marshal;
  Parallel = System.Threading.Tasks.Parallel;
  Action =  system.Action;
  
  GaussianBlur = class
      _red:array of integer;
      _green: array of integer;
      _blue: array of integer;
      
      _width:integer;
      _height:integer;
      
      procedure GaussianBlur(image:Bitmap);
        begin
          var rct:Rectangle := new Rectangle(0, 0, image.Width, image.Height);
          var source:array of integer := new integer[rct.Width * rct.Height];
          var bits:BitmapData := image.LockBits(rct, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
          Marshal.Copy(bits.Scan0, source, 0, source.Length);
          image.UnlockBits(bits);

          _width :=  image.Width;
          _height := image.Height;

          _red :=   new integer[_width*_height];
          _green := new integer[_width*_height];
          _blue :=  new integer[_width*_height];
          
          {$omp parallel for}
          For var i := 0 to source.Length-1 do begin
            _red[i] :=    (source[i] and $ff0000) shr 16; //R
            _green[i] :=  (source[i] and $00ff00) shr 8; //G
            _blue[i] :=   (source[i] and $0000ff); //B
          end;
        end;

      function Process(radial:integer):Bitmap;
      begin
        var newRed:   array of integer = new integer[_width * _height];
        var newGreen: array of integer = new integer[_width * _height];
        var newBlue:  array of integer = new integer[_width * _height];
        var dest:     array of integer = new integer[_width * _height];
        
        { $omp parallel sections} // выполн€ютс€ параллельно
        { TODO
        Parallel.Invoke(
        () -> gaussBlur_4(_red, newRed, radial),
        () -> gaussBlur_4(_green, newGreen, radial),
        () -> gaussBlur_4(_blue, newBlue, radial));
        }
        
        gaussBlur_4(_red, newRed, radial);
        gaussBlur_4(_green, newGreen, radial);
        gaussBlur_4(_blue, newBlue, radial);
        
        // нормализаци€. готовим integer дл€ перевода в byte
        {$omp parallel for}
        For var i := 0 to dest.Length-1 do begin
          if (newRed[i] > 255) then newRed[i] := 255;
          if (newGreen[i] > 255) then newGreen[i] := 255;
          if (newBlue[i] > 255) then newBlue[i] := 255;
  
          if (newRed[i] < 0) then newRed[i] := 0;
          if (newGreen[i] < 0) then newGreen[i] := 0;
          if (newBlue[i] < 0) then newBlue[i] := 0;
          
          //dest[i] := integer($ff000000 or integer(newRed[i] shl 16) or integer(newGreen[i] shl 8) or integer(newBlue[i]) );
          dest[i] := RGB(newRed[i],newGreen[i],newBlue[i]).ToArgb;
        end;
  
        var image:Bitmap := new Bitmap(_width, _height);
        var rct:Rectangle := new Rectangle(0, 0, image.Width, image.Height);
        var bits2 := image.LockBits(rct, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
        Marshal.Copy(dest, 0, bits2.Scan0, dest.Length);
        image.UnlockBits(bits2);
        
        result := image;
      end;

      function boxesForGauss(sigma:integer; n:integer):array of integer;
      begin
        var wIdeal:real := Sqrt((12 * sigma * sigma / n) + 1);
        var wl:integer := Floor(wIdeal);
        if (wl mod 2 = 0) then dec(wl);
        var wu:integer := wl + 2;
  
        var mIdeal:real := (12 * sigma * sigma - n * wl * wl - 4 * n * wl - 3 * n) / (-4 * wl - 4);
        var m:integer := Round(mIdeal);
  
        var sizes:List<integer> := new List<integer>();
        for var i := 0 to n-1 do sizes.Add(i<m?wl:wu);
        result := sizes.ToArray();
      end;

      procedure gaussBlur_4(source:array of integer; dest:array of integer; r:integer);
      begin
        var bxs:array of integer := boxesForGauss(r, 3);
        boxBlur_4(source, dest, _width, _height, (bxs[0] - 1) div 2);
        boxBlur_4(dest, source, _width, _height, (bxs[1] - 1) div 2);
        boxBlur_4(source, dest, _width, _height, (bxs[2] - 1) div 2);
      end;

      procedure boxBlur_4(source:array of integer; dest:array of integer; w:integer; h:integer; r:integer);
      begin
        for var i := 0 to source.Length-1 do dest[i] := source[i];
        boxBlurH_4(dest, source, w, h, r);
        boxBlurT_4(source, dest, w, h, r);
      end;

      procedure boxBlurH_4(source:array of integer; dest:array of integer; w:integer; h:integer; r:integer);
      begin
          var iar:real := 1 / (r + r + 1);
          {$omp parallel for}
          For var i := 0 to h-1 do begin
              var ti:integer := i * w;
              var li:integer := ti;
              var ri:integer := ti + r;
              var fv:integer := source[ti];
              var lv:integer := source[ti + w - 1];
              var val:integer := (r + 1) * fv;
              for var j := 0 to r-1 do val += source[ti + j];
              for var j := 0 to r do begin
                  val += source[ri] - fv; inc(ri);
                  dest[ti] := Round(val * iar); inc(ti);
              end;
              for var j := r + 1 to (w - r -1) do begin
                  val += source[ri] - dest[li]; inc(ri); inc(li);
                  dest[ti] := Round(val * iar); inc(ti);
              end;
              for var j := w - r to w-1 do begin
                  val += lv - source[li]; inc(li);
                  dest[ti] := Round(val * iar); inc(ti);
              end;
          end;
      end;

      procedure boxBlurT_4(source:array of integer; dest:array of integer; w:integer; h:integer; r:integer);
      begin
          var iar:real := 1 / (r + r + 1);
          {$omp parallel for}
          For var i := 0 to w-1 do begin
              var ti:integer := i;
              var li:integer := ti;
              var ri:integer := ti + r * w;
              var fv:integer := source[ti];
              var lv:integer := source[ti + w * (h - 1)];
              var val:integer := (r + 1) * fv;
              for var j := 0 to r-1 do val += source[ti + j * w];
              for var j := 0 to r do begin
                  val += source[ri] - fv;
                  dest[ti] := Round(val * iar);
                  ri += w;
                  ti += w;
              end;
              for var j := (r + 1) to (h - r -1) do begin
                  val += (source[ri] - source[li]);
                  dest[ti] := Round(val * iar);
                  li += w;
                  ri += w;
                  ti += w;
              end;
              for var j := h - r to h-1 do begin
                  val += lv - source[li];
                  dest[ti] := Round(val * iar);
                  li += w;
                  ti += w;
              end;
          end;
      end;
    end;
    
BEGIN
var p:picture := new Picture('sample.bmp');
window.Width := 2*p.Width+1;
window.Height := p.Height;
p.Draw(0,0);
var r := 20;
var gb:GaussianBlur := new GaussianBlur;
var tt:Stopwatch := new Stopwatch;
tt.Start;
gb.GaussianBlur(p.bmp);
p.bmp:=gb.Process(r);
tt.Stop;
writeln('Fastest Gaussian Blur(with LockBits+Marshal.copy):');
writeln(' R: ',r,'px');
writeln(' Time: ',tt.ElapsedMilliseconds,'ms');
writeln(' Size: ',p.Width,'x',p.Height,'px');
p.Draw(p.Width+1,0);  
END.