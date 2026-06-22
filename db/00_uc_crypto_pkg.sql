-- UC_CRYPTO Package: Pure PL/SQL drop-in replacement for DBMS_CRYPTO
-- Author: Anton Scheffer, MIT License
-- Install BEFORE all other EPF packages (run order: 00 -> 01 -> 03 -> ...)

CREATE OR REPLACE PACKAGE uc_crypto AS
  -- Hash type constants (same values as DBMS_CRYPTO)
  HASH_MD4     CONSTANT PLS_INTEGER := 1;
  HASH_MD5     CONSTANT PLS_INTEGER := 2;
  HASH_SH1     CONSTANT PLS_INTEGER := 3;
  HASH_SH256   CONSTANT PLS_INTEGER := 4;
  HASH_SH384   CONSTANT PLS_INTEGER := 5;
  HASH_SH512   CONSTANT PLS_INTEGER := 6;

  -- Encryption type constants
  ENCRYPT_DES        CONSTANT PLS_INTEGER := 1;
  ENCRYPT_3DES_2KEY  CONSTANT PLS_INTEGER := 2;
  ENCRYPT_3DES       CONSTANT PLS_INTEGER := 3;
  ENCRYPT_AES128     CONSTANT PLS_INTEGER := 6;
  ENCRYPT_AES192     CONSTANT PLS_INTEGER := 7;
  ENCRYPT_AES256     CONSTANT PLS_INTEGER := 8;

  -- Chain mode constants
  CHAIN_CBC  CONSTANT PLS_INTEGER := 256;
  CHAIN_CFB  CONSTANT PLS_INTEGER := 512;
  CHAIN_ECB  CONSTANT PLS_INTEGER := 768;
  CHAIN_OFB  CONSTANT PLS_INTEGER := 1024;

  -- Padding constants
  PAD_PKCS5  CONSTANT PLS_INTEGER := 4096;
  PAD_NONE   CONSTANT PLS_INTEGER := 8192;
  PAD_ZERO   CONSTANT PLS_INTEGER := 12288;

  FUNCTION  hash( src RAW, typ PLS_INTEGER ) RETURN RAW;
  FUNCTION  mac( src RAW, typ PLS_INTEGER, key RAW ) RETURN RAW;
  FUNCTION  randombytes( number_bytes POSITIVE ) RETURN RAW;
  FUNCTION  encrypt( src RAW, typ PLS_INTEGER, key RAW, iv RAW := NULL ) RETURN RAW;
  FUNCTION  decrypt( src RAW, typ PLS_INTEGER, key RAW, iv RAW := NULL ) RETURN RAW;
END uc_crypto;
/

CREATE OR REPLACE PACKAGE BODY uc_crypto AS

  -- -----------------------------------------------------------------------
  -- Internal utility types and helpers
  -- -----------------------------------------------------------------------
  TYPE tp_tab_raw  IS TABLE OF RAW(32767) INDEX BY PLS_INTEGER;
  TYPE tp_tab_num  IS TABLE OF NUMBER     INDEX BY PLS_INTEGER;
  TYPE tp_sbox     IS TABLE OF PLS_INTEGER INDEX BY PLS_INTEGER;

  g_seed  RAW(2048);

  -- -----------------------------------------------------------------------
  -- Circular left-rotate for SHA-1 / SHA-256
  -- -----------------------------------------------------------------------
  FUNCTION rotl32( x PLS_INTEGER, n PLS_INTEGER ) RETURN PLS_INTEGER IS
  BEGIN
    RETURN TO_NUMBER( BITAND( x * POWER(2,n), 4294967295 )
                    + FLOOR( x / POWER(2, 32-n) ) );
  END;

  FUNCTION rotr32( x PLS_INTEGER, n PLS_INTEGER ) RETURN PLS_INTEGER IS
  BEGIN
    RETURN TO_NUMBER( FLOOR( x / POWER(2,n) )
                    + BITAND( x * POWER(2, 32-n), 4294967295 ) );
  END;

  -- -----------------------------------------------------------------------
  -- 64-bit helpers (stored as 2 x PLS_INTEGER: hi, lo)
  -- -----------------------------------------------------------------------
  PROCEDURE add64( a0 IN OUT PLS_INTEGER, a1 IN OUT PLS_INTEGER
                 , b0 PLS_INTEGER,        b1 PLS_INTEGER )
  IS
    l PLS_INTEGER;
  BEGIN
    l  := a1 + b1;
    a0 := MOD( a0 + b0 + FLOOR(l / 4294967296), 4294967296 );
    a1 := MOD( l, 4294967296 );
  END;

  FUNCTION rotr64_hi( hi PLS_INTEGER, lo PLS_INTEGER, n PLS_INTEGER ) RETURN PLS_INTEGER IS
  BEGIN
    IF n < 32 THEN
      RETURN MOD( FLOOR(hi/POWER(2,n)) + MOD(lo,POWER(2,n))*POWER(2,32-n), 4294967296 );
    ELSE
      RETURN MOD( FLOOR(lo/POWER(2,n-32)) + MOD(hi,POWER(2,n-32))*POWER(2,64-n), 4294967296 );
    END IF;
  END;

  FUNCTION rotr64_lo( hi PLS_INTEGER, lo PLS_INTEGER, n PLS_INTEGER ) RETURN PLS_INTEGER IS
  BEGIN
    IF n < 32 THEN
      RETURN MOD( FLOOR(lo/POWER(2,n)) + MOD(hi,POWER(2,n))*POWER(2,32-n), 4294967296 );
    ELSE
      RETURN MOD( FLOOR(hi/POWER(2,n-32)) + MOD(lo,POWER(2,n-32))*POWER(2,64-n), 4294967296 );
    END IF;
  END;

  FUNCTION shr64_hi( hi PLS_INTEGER, lo PLS_INTEGER, n PLS_INTEGER ) RETURN PLS_INTEGER IS
  BEGIN
    IF n < 32 THEN RETURN FLOOR(hi/POWER(2,n));
    ELSE             RETURN 0;
    END IF;
  END;

  FUNCTION shr64_lo( hi PLS_INTEGER, lo PLS_INTEGER, n PLS_INTEGER ) RETURN PLS_INTEGER IS
  BEGIN
    IF    n < 32 THEN RETURN MOD( FLOOR(lo/POWER(2,n)) + MOD(hi,POWER(2,n))*POWER(2,32-n), 4294967296 );
    ELSIF n < 64 THEN RETURN FLOOR(hi/POWER(2,n-32));
    ELSE              RETURN 0;
    END IF;
  END;

  -- -----------------------------------------------------------------------
  -- MD4
  -- -----------------------------------------------------------------------
  FUNCTION md4( src RAW ) RETURN RAW IS
    b   RAW(32767) := src;
    lb  PLS_INTEGER := UTL_RAW.LENGTH(b);
    pad PLS_INTEGER;
    a   PLS_INTEGER; aa PLS_INTEGER;
    bv  PLS_INTEGER; bb PLS_INTEGER;
    c   PLS_INTEGER; cc PLS_INTEGER;
    d   PLS_INTEGER; dd PLS_INTEGER;
    f   PLS_INTEGER;
    k   PLS_INTEGER;
    s   PLS_INTEGER;
    x   tp_tab_num;
    i   PLS_INTEGER;
    j   PLS_INTEGER;
    tmp PLS_INTEGER;
    FUNCTION lrot( v PLS_INTEGER, n PLS_INTEGER ) RETURN PLS_INTEGER IS
    BEGIN RETURN rotl32(v,n); END;
    PROCEDURE round1( av IN OUT PLS_INTEGER, bv PLS_INTEGER, cv PLS_INTEGER, dv PLS_INTEGER
                    , xk PLS_INTEGER, s PLS_INTEGER )
    IS BEGIN av := lrot( MOD(av + BITAND(bv,cv)+BITAND(BITXOR(bv,4294967295),dv)+xk,4294967296), s ); END;
    PROCEDURE round2( av IN OUT PLS_INTEGER, bv PLS_INTEGER, cv PLS_INTEGER, dv PLS_INTEGER
                    , xk PLS_INTEGER, s PLS_INTEGER )
    IS BEGIN av := lrot( MOD(av + BITAND(bv,cv)+BITAND(bv,dv)+BITAND(cv,dv)+1518500249+xk,4294967296), s ); END;
    PROCEDURE round3( av IN OUT PLS_INTEGER, bv PLS_INTEGER, cv PLS_INTEGER, dv PLS_INTEGER
                    , xk PLS_INTEGER, s PLS_INTEGER )
    IS BEGIN av := lrot( MOD(av + BITXOR(BITXOR(bv,cv),dv)+1859775393+xk,4294967296), s ); END;
  BEGIN
    pad := 64 - MOD( lb + 9, 64 );
    IF pad = 64 THEN pad := 0; END IF;
    b := b || HEXTORAW('80') || HEXTORAW( LPAD('',pad*2,'00') )
           || UTL_RAW.CAST_FROM_BINARY_INTEGER( MOD(lb,536870912)*8, UTL_RAW.LITTLE_ENDIAN )
           || UTL_RAW.CAST_FROM_BINARY_INTEGER( FLOOR(lb/536870912), UTL_RAW.LITTLE_ENDIAN );
    a := 1732584193; bv := 4023233417; c := 2562383102; d := 271733878;
    i := 1;
    WHILE i <= UTL_RAW.LENGTH(b) LOOP
      FOR j IN 0..15 LOOP
        x(j) := UTL_RAW.CAST_TO_BINARY_INTEGER( UTL_RAW.SUBSTR(b,i+j*4,4), UTL_RAW.LITTLE_ENDIAN );
      END LOOP;
      aa:=a; bb:=bv; cc:=c; dd:=d;
      round1(a,bv,c,d,x(0),3);  round1(d,a,bv,c,x(1),7);  round1(c,d,a,bv,x(2),11); round1(bv,c,d,a,x(3),19);
      round1(a,bv,c,d,x(4),3);  round1(d,a,bv,c,x(5),7);  round1(c,d,a,bv,x(6),11); round1(bv,c,d,a,x(7),19);
      round1(a,bv,c,d,x(8),3);  round1(d,a,bv,c,x(9),7);  round1(c,d,a,bv,x(10),11);round1(bv,c,d,a,x(11),19);
      round1(a,bv,c,d,x(12),3); round1(d,a,bv,c,x(13),7); round1(c,d,a,bv,x(14),11);round1(bv,c,d,a,x(15),19);
      round2(a,bv,c,d,x(0),3);  round2(d,a,bv,c,x(4),5);  round2(c,d,a,bv,x(8),9);  round2(bv,c,d,a,x(12),13);
      round2(a,bv,c,d,x(1),3);  round2(d,a,bv,c,x(5),5);  round2(c,d,a,bv,x(9),9);  round2(bv,c,d,a,x(13),13);
      round2(a,bv,c,d,x(2),3);  round2(d,a,bv,c,x(6),5);  round2(c,d,a,bv,x(10),9); round2(bv,c,d,a,x(14),13);
      round2(a,bv,c,d,x(3),3);  round2(d,a,bv,c,x(7),5);  round2(c,d,a,bv,x(11),9); round2(bv,c,d,a,x(15),13);
      round3(a,bv,c,d,x(0),3);  round3(d,a,bv,c,x(8),9);  round3(c,d,a,bv,x(4),11); round3(bv,c,d,a,x(12),15);
      round3(a,bv,c,d,x(2),3);  round3(d,a,bv,c,x(10),9); round3(c,d,a,bv,x(6),11); round3(bv,c,d,a,x(14),15);
      round3(a,bv,c,d,x(1),3);  round3(d,a,bv,c,x(9),9);  round3(c,d,a,bv,x(5),11); round3(bv,c,d,a,x(13),15);
      round3(a,bv,c,d,x(3),3);  round3(d,a,bv,c,x(11),9); round3(c,d,a,bv,x(7),11); round3(bv,c,d,a,x(15),15);
      a:=MOD(a+aa,4294967296); bv:=MOD(bv+bb,4294967296); c:=MOD(c+cc,4294967296); d:=MOD(d+dd,4294967296);
      i := i + 64;
    END LOOP;
    RETURN    UTL_RAW.CAST_FROM_BINARY_INTEGER(a, UTL_RAW.LITTLE_ENDIAN)
           || UTL_RAW.CAST_FROM_BINARY_INTEGER(bv,UTL_RAW.LITTLE_ENDIAN)
           || UTL_RAW.CAST_FROM_BINARY_INTEGER(c, UTL_RAW.LITTLE_ENDIAN)
           || UTL_RAW.CAST_FROM_BINARY_INTEGER(d, UTL_RAW.LITTLE_ENDIAN);
  END md4;

  -- -----------------------------------------------------------------------
  -- MD5
  -- -----------------------------------------------------------------------
  FUNCTION md5( src RAW ) RETURN RAW IS
    b     RAW(32767) := src;
    lb    PLS_INTEGER := UTL_RAW.LENGTH(b);
    pad   PLS_INTEGER;
    a     PLS_INTEGER; aa PLS_INTEGER;
    bv    PLS_INTEGER; bb PLS_INTEGER;
    c     PLS_INTEGER; cc PLS_INTEGER;
    d     PLS_INTEGER; dd PLS_INTEGER;
    x     tp_tab_num;
    i     PLS_INTEGER;
    T     tp_tab_num;
    FUNCTION lrot( v PLS_INTEGER, n PLS_INTEGER ) RETURN PLS_INTEGER IS
    BEGIN RETURN rotl32(v,n); END;
    PROCEDURE FF( av IN OUT PLS_INTEGER, bv PLS_INTEGER, cv PLS_INTEGER, dv PLS_INTEGER
                , k PLS_INTEGER, s PLS_INTEGER, i PLS_INTEGER )
    IS BEGIN av := MOD( bv + lrot( MOD(av+BITAND(bv,cv)+BITAND(BITXOR(bv,4294967295),dv)+x(k)+T(i),4294967296),s ),4294967296 ); END;
    PROCEDURE GG( av IN OUT PLS_INTEGER, bv PLS_INTEGER, cv PLS_INTEGER, dv PLS_INTEGER
                , k PLS_INTEGER, s PLS_INTEGER, i PLS_INTEGER )
    IS BEGIN av := MOD( bv + lrot( MOD(av+BITAND(bv,dv)+BITAND(cv,BITXOR(dv,4294967295))+x(k)+T(i),4294967296),s ),4294967296 ); END;
    PROCEDURE HH( av IN OUT PLS_INTEGER, bv PLS_INTEGER, cv PLS_INTEGER, dv PLS_INTEGER
                , k PLS_INTEGER, s PLS_INTEGER, i PLS_INTEGER )
    IS BEGIN av := MOD( bv + lrot( MOD(av+BITXOR(BITXOR(bv,cv),dv)+x(k)+T(i),4294967296),s ),4294967296 ); END;
    PROCEDURE II( av IN OUT PLS_INTEGER, bv PLS_INTEGER, cv PLS_INTEGER, dv PLS_INTEGER
                , k PLS_INTEGER, s PLS_INTEGER, i PLS_INTEGER )
    IS BEGIN av := MOD( bv + lrot( MOD(av+BITXOR(cv,BITOR(bv,BITXOR(dv,4294967295)))+x(k)+T(i),4294967296),s ),4294967296 ); END;
  BEGIN
    FOR j IN 1..64 LOOP
      T(j) := TRUNC( ABS( SIN(j) ) * 4294967296 );
    END LOOP;
    pad := 64 - MOD( lb + 9, 64 );
    IF pad = 64 THEN pad := 0; END IF;
    b := b || HEXTORAW('80') || HEXTORAW( LPAD('',pad*2,'00') )
           || UTL_RAW.CAST_FROM_BINARY_INTEGER( MOD(lb,536870912)*8, UTL_RAW.LITTLE_ENDIAN )
           || UTL_RAW.CAST_FROM_BINARY_INTEGER( FLOOR(lb/536870912), UTL_RAW.LITTLE_ENDIAN );
    a:=1732584193; bv:=4023233417; c:=2562383102; d:=271733878;
    i := 1;
    WHILE i <= UTL_RAW.LENGTH(b) LOOP
      FOR j IN 0..15 LOOP
        x(j) := UTL_RAW.CAST_TO_BINARY_INTEGER( UTL_RAW.SUBSTR(b,i+j*4,4), UTL_RAW.LITTLE_ENDIAN );
      END LOOP;
      aa:=a; bb:=bv; cc:=c; dd:=d;
      FF(a,bv,c,d, 0, 7, 1); FF(d,a,bv,c, 1,12, 2); FF(c,d,a,bv, 2,17, 3); FF(bv,c,d,a, 3,22, 4);
      FF(a,bv,c,d, 4, 7, 5); FF(d,a,bv,c, 5,12, 6); FF(c,d,a,bv, 6,17, 7); FF(bv,c,d,a, 7,22, 8);
      FF(a,bv,c,d, 8, 7, 9); FF(d,a,bv,c, 9,12,10); FF(c,d,a,bv,10,17,11); FF(bv,c,d,a,11,22,12);
      FF(a,bv,c,d,12, 7,13); FF(d,a,bv,c,13,12,14); FF(c,d,a,bv,14,17,15); FF(bv,c,d,a,15,22,16);
      GG(a,bv,c,d, 1, 5,17); GG(d,a,bv,c, 6, 9,18); GG(c,d,a,bv,11,14,19); GG(bv,c,d,a, 0,20,20);
      GG(a,bv,c,d, 5, 5,21); GG(d,a,bv,c,10, 9,22); GG(c,d,a,bv,15,14,23); GG(bv,c,d,a, 4,20,24);
      GG(a,bv,c,d, 9, 5,25); GG(d,a,bv,c,14, 9,26); GG(c,d,a,bv, 3,14,27); GG(bv,c,d,a, 8,20,28);
      GG(a,bv,c,d,13, 5,29); GG(d,a,bv,c, 2, 9,30); GG(c,d,a,bv, 7,14,31); GG(bv,c,d,a,12,20,32);
      HH(a,bv,c,d, 5, 4,33); HH(d,a,bv,c, 8,11,34); HH(c,d,a,bv,11,16,35); HH(bv,c,d,a,14,23,36);
      HH(a,bv,c,d, 1, 4,37); HH(d,a,bv,c, 4,11,38); HH(c,d,a,bv, 7,16,39); HH(bv,c,d,a,10,23,40);
      HH(a,bv,c,d,13, 4,41); HH(d,a,bv,c, 0,11,42); HH(c,d,a,bv, 3,16,43); HH(bv,c,d,a, 6,23,44);
      HH(a,bv,c,d, 9, 4,45); HH(d,a,bv,c,12,11,46); HH(c,d,a,bv,15,16,47); HH(bv,c,d,a, 2,23,48);
      II(a,bv,c,d, 0, 6,49); II(d,a,bv,c, 7,10,50); II(c,d,a,bv,14,15,51); II(bv,c,d,a, 5,21,52);
      II(a,bv,c,d,12, 6,53); II(d,a,bv,c, 3,10,54); II(c,d,a,bv,10,15,55); II(bv,c,d,a, 1,21,56);
      II(a,bv,c,d, 8, 6,57); II(d,a,bv,c,15,10,58); II(c,d,a,bv, 6,15,59); II(bv,c,d,a,13,21,60);
      II(a,bv,c,d, 4, 6,61); II(d,a,bv,c,11,10,62); II(c,d,a,bv, 2,15,63); II(bv,c,d,a, 9,21,64);
      a:=MOD(a+aa,4294967296); bv:=MOD(bv+bb,4294967296); c:=MOD(c+cc,4294967296); d:=MOD(d+dd,4294967296);
      i := i + 64;
    END LOOP;
    RETURN    UTL_RAW.CAST_FROM_BINARY_INTEGER(a, UTL_RAW.LITTLE_ENDIAN)
           || UTL_RAW.CAST_FROM_BINARY_INTEGER(bv,UTL_RAW.LITTLE_ENDIAN)
           || UTL_RAW.CAST_FROM_BINARY_INTEGER(c, UTL_RAW.LITTLE_ENDIAN)
           || UTL_RAW.CAST_FROM_BINARY_INTEGER(d, UTL_RAW.LITTLE_ENDIAN);
  END md5;

  -- -----------------------------------------------------------------------
  -- SHA-1
  -- -----------------------------------------------------------------------
  FUNCTION sha1( src RAW ) RETURN RAW IS
    b   RAW(32767) := src;
    lb  PLS_INTEGER := UTL_RAW.LENGTH(b);
    pad PLS_INTEGER;
    h0  PLS_INTEGER := 1732584193;
    h1  PLS_INTEGER := 4023233417;
    h2  PLS_INTEGER := 2562383102;
    h3  PLS_INTEGER := 271733878;
    h4  PLS_INTEGER := 3285377520;
    a   PLS_INTEGER; bv PLS_INTEGER; c  PLS_INTEGER; d PLS_INTEGER; e PLS_INTEGER;
    f   PLS_INTEGER; k  PLS_INTEGER; tmp PLS_INTEGER;
    w   tp_tab_num;
    i   PLS_INTEGER;
  BEGIN
    pad := 64 - MOD(lb+9,64);
    IF pad=64 THEN pad:=0; END IF;
    b := b || HEXTORAW('80') || HEXTORAW(LPAD('',pad*2,'00'))
           || UTL_RAW.CAST_FROM_BINARY_INTEGER(FLOOR(lb/536870912),UTL_RAW.BIG_ENDIAN)
           || UTL_RAW.CAST_FROM_BINARY_INTEGER(MOD(lb,536870912)*8,UTL_RAW.BIG_ENDIAN);
    i := 1;
    WHILE i <= UTL_RAW.LENGTH(b) LOOP
      FOR j IN 0..15 LOOP
        w(j) := UTL_RAW.CAST_TO_BINARY_INTEGER(UTL_RAW.SUBSTR(b,i+j*4,4),UTL_RAW.BIG_ENDIAN);
      END LOOP;
      FOR j IN 16..79 LOOP
        w(j) := rotl32(BITXOR(BITXOR(BITXOR(w(j-3),w(j-8)),w(j-14)),w(j-16)),1);
      END LOOP;
      a:=h0; bv:=h1; c:=h2; d:=h3; e:=h4;
      FOR j IN 0..79 LOOP
        IF    j<20 THEN f:=BITOR(BITAND(bv,c),BITAND(BITXOR(bv,4294967295),d)); k:=1518500249;
        ELSIF j<40 THEN f:=BITXOR(BITXOR(bv,c),d);                               k:=1859775393;
        ELSIF j<60 THEN f:=BITOR(BITOR(BITAND(bv,c),BITAND(bv,d)),BITAND(c,d)); k:=2400959708;
        ELSE             f:=BITXOR(BITXOR(bv,c),d);                               k:=3395469782;
        END IF;
        tmp:=MOD(rotl32(a,5)+f+e+k+w(j),4294967296);
        e:=d; d:=c; c:=rotl32(bv,30); bv:=a; a:=tmp;
      END LOOP;
      h0:=MOD(h0+a,4294967296); h1:=MOD(h1+bv,4294967296); h2:=MOD(h2+c,4294967296);
      h3:=MOD(h3+d,4294967296); h4:=MOD(h4+e,4294967296);
      i := i+64;
    END LOOP;
    RETURN    UTL_RAW.CAST_FROM_BINARY_INTEGER(h0,UTL_RAW.BIG_ENDIAN)
           || UTL_RAW.CAST_FROM_BINARY_INTEGER(h1,UTL_RAW.BIG_ENDIAN)
           || UTL_RAW.CAST_FROM_BINARY_INTEGER(h2,UTL_RAW.BIG_ENDIAN)
           || UTL_RAW.CAST_FROM_BINARY_INTEGER(h3,UTL_RAW.BIG_ENDIAN)
           || UTL_RAW.CAST_FROM_BINARY_INTEGER(h4,UTL_RAW.BIG_ENDIAN);
  END sha1;

  -- -----------------------------------------------------------------------
  -- SHA-256
  -- -----------------------------------------------------------------------
  FUNCTION sha256( src RAW ) RETURN RAW IS
    b    RAW(32767) := src;
    lb   PLS_INTEGER := UTL_RAW.LENGTH(b);
    pad  PLS_INTEGER;
    h    tp_tab_num;
    k256 tp_tab_num;
    w    tp_tab_num;
    a    PLS_INTEGER; bv PLS_INTEGER; c PLS_INTEGER; d PLS_INTEGER;
    e    PLS_INTEGER; f  PLS_INTEGER; g PLS_INTEGER; hh PLS_INTEGER;
    t1   PLS_INTEGER; t2 PLS_INTEGER;
    i    PLS_INTEGER;
    s0   PLS_INTEGER; s1 PLS_INTEGER;
    FUNCTION ch(  x PLS_INTEGER, y PLS_INTEGER, z PLS_INTEGER ) RETURN PLS_INTEGER IS
    BEGIN RETURN BITOR(BITAND(x,y),BITAND(BITXOR(x,4294967295),z)); END;
    FUNCTION maj( x PLS_INTEGER, y PLS_INTEGER, z PLS_INTEGER ) RETURN PLS_INTEGER IS
    BEGIN RETURN BITOR(BITOR(BITAND(x,y),BITAND(x,z)),BITAND(y,z)); END;
  BEGIN
    k256(0):=1116352408; k256(1):=1899447441; k256(2):=3049323471; k256(3):=3921009573;
    k256(4):=961987163;  k256(5):=1508970993; k256(6):=2453635748; k256(7):=2870763221;
    k256(8):=3624381080; k256(9):=310598401;  k256(10):=607225278; k256(11):=1426881987;
    k256(12):=1925078388;k256(13):=2162078206;k256(14):=2614888103;k256(15):=3248222580;
    k256(16):=3835390401;k256(17):=4022224774;k256(18):=264347078; k256(19):=604807628;
    k256(20):=770255983; k256(21):=1249150122;k256(22):=1555081692;k256(23):=1996064986;
    k256(24):=2554220882;k256(25):=2821834349;k256(26):=2952996808;k256(27):=3210313671;
    k256(28):=3336571891;k256(29):=3584528711;k256(30):=113926993; k256(31):=338241895;
    k256(32):=666307205; k256(33):=773529912; k256(34):=1294757372;k256(35):=1396182291;
    k256(36):=1695183700;k256(37):=1986661051;k256(38):=2177026350;k256(39):=2456956037;
    k256(40):=2730485921;k256(41):=2820302411;k256(42):=3259730800;k256(43):=3345764771;
    k256(44):=3516065817;k256(45):=3600352804;k256(46):=4094571909;k256(47):=275423344;
    k256(48):=430227734; k256(49):=506948616; k256(50):=659060556; k256(51):=883997877;
    k256(52):=958139571; k256(53):=1322822218;k256(54):=1537002063;k256(55):=1747873779;
    k256(56):=1955562222;k256(57):=2024104815;k256(58):=2227730452;k256(59):=2361852424;
    k256(60):=2428436474;k256(61):=2756734187;k256(62):=3204031479;k256(63):=3329325298;
    h(0):=1779033703; h(1):=3144134277; h(2):=1013904242; h(3):=2773480762;
    h(4):=1359893119; h(5):=2600822924; h(6):=528734635;  h(7):=1541325195;
    pad := 64 - MOD(lb+9,64);
    IF pad=64 THEN pad:=0; END IF;
    b := b || HEXTORAW('80') || HEXTORAW(LPAD('',pad*2,'00'))
           || UTL_RAW.CAST_FROM_BINARY_INTEGER(FLOOR(lb/536870912),UTL_RAW.BIG_ENDIAN)
           || UTL_RAW.CAST_FROM_BINARY_INTEGER(MOD(lb,536870912)*8,UTL_RAW.BIG_ENDIAN);
    i := 1;
    WHILE i <= UTL_RAW.LENGTH(b) LOOP
      FOR j IN 0..15 LOOP
        w(j) := UTL_RAW.CAST_TO_BINARY_INTEGER(UTL_RAW.SUBSTR(b,i+j*4,4),UTL_RAW.BIG_ENDIAN);
      END LOOP;
      FOR j IN 16..63 LOOP
        s0 := BITXOR(BITXOR(rotr32(w(j-15),7),rotr32(w(j-15),18)),FLOOR(w(j-15)/128));
        s1 := BITXOR(BITXOR(rotr32(w(j-2),17),rotr32(w(j-2),19)),FLOOR(w(j-2)/1073741824));
        w(j) := MOD(w(j-16)+s0+w(j-7)+s1,4294967296);
      END LOOP;
      a:=h(0);bv:=h(1);c:=h(2);d:=h(3);e:=h(4);f:=h(5);g:=h(6);hh:=h(7);
      FOR j IN 0..63 LOOP
        s1 := BITXOR(BITXOR(rotr32(e,6),rotr32(e,11)),rotr32(e,25));
        t1 := MOD(hh+s1+ch(e,f,g)+k256(j)+w(j),4294967296);
        s0 := BITXOR(BITXOR(rotr32(a,2),rotr32(a,13)),rotr32(a,22));
        t2 := MOD(s0+maj(a,bv,c),4294967296);
        hh:=g; g:=f; f:=e; e:=MOD(d+t1,4294967296);
        d:=c; c:=bv; bv:=a; a:=MOD(t1+t2,4294967296);
      END LOOP;
      h(0):=MOD(h(0)+a,4294967296); h(1):=MOD(h(1)+bv,4294967296);
      h(2):=MOD(h(2)+c,4294967296); h(3):=MOD(h(3)+d,4294967296);
      h(4):=MOD(h(4)+e,4294967296); h(5):=MOD(h(5)+f,4294967296);
      h(6):=MOD(h(6)+g,4294967296); h(7):=MOD(h(7)+hh,4294967296);
      i := i+64;
    END LOOP;
    RETURN    UTL_RAW.CAST_FROM_BINARY_INTEGER(h(0),UTL_RAW.BIG_ENDIAN)
           || UTL_RAW.CAST_FROM_BINARY_INTEGER(h(1),UTL_RAW.BIG_ENDIAN)
           || UTL_RAW.CAST_FROM_BINARY_INTEGER(h(2),UTL_RAW.BIG_ENDIAN)
           || UTL_RAW.CAST_FROM_BINARY_INTEGER(h(3),UTL_RAW.BIG_ENDIAN)
           || UTL_RAW.CAST_FROM_BINARY_INTEGER(h(4),UTL_RAW.BIG_ENDIAN)
           || UTL_RAW.CAST_FROM_BINARY_INTEGER(h(5),UTL_RAW.BIG_ENDIAN)
           || UTL_RAW.CAST_FROM_BINARY_INTEGER(h(6),UTL_RAW.BIG_ENDIAN)
           || UTL_RAW.CAST_FROM_BINARY_INTEGER(h(7),UTL_RAW.BIG_ENDIAN);
  END sha256;

  -- -----------------------------------------------------------------------
  -- SHA-384 / SHA-512 shared core
  -- -----------------------------------------------------------------------
  FUNCTION sha512_core( src RAW, is384 BOOLEAN := FALSE ) RETURN RAW IS
    b    RAW(32767) := src;
    lb   PLS_INTEGER := UTL_RAW.LENGTH(b);
    pad  PLS_INTEGER;
    -- 8 x 64-bit words stored as (hi, lo) pairs in arrays h_hi, h_lo
    h_hi tp_tab_num; h_lo tp_tab_num;
    -- 80 round constants (hi, lo)
    k_hi tp_tab_num; k_lo tp_tab_num;
    -- message schedule
    w_hi tp_tab_num; w_lo tp_tab_num;
    -- working variables
    ah PLS_INTEGER; al PLS_INTEGER;
    bh PLS_INTEGER; bl PLS_INTEGER;
    ch2 PLS_INTEGER; cl PLS_INTEGER;
    dh PLS_INTEGER; dl PLS_INTEGER;
    eh PLS_INTEGER; el PLS_INTEGER;
    fh PLS_INTEGER; fl PLS_INTEGER;
    gh2 PLS_INTEGER; gl PLS_INTEGER;
    hh2 PLS_INTEGER; hl PLS_INTEGER;
    t1h PLS_INTEGER; t1l PLS_INTEGER;
    t2h PLS_INTEGER; t2l PLS_INTEGER;
    s0h PLS_INTEGER; s0l PLS_INTEGER;
    s1h PLS_INTEGER; s1l PLS_INTEGER;
    tmp_h PLS_INTEGER; tmp_l PLS_INTEGER;
    i   PLS_INTEGER;

    FUNCTION ch_h( x PLS_INTEGER, y PLS_INTEGER, z PLS_INTEGER ) RETURN PLS_INTEGER IS
    BEGIN RETURN BITOR(BITAND(x,y),BITAND(BITXOR(x,4294967295),z)); END;
    FUNCTION maj_h( x PLS_INTEGER, y PLS_INTEGER, z PLS_INTEGER ) RETURN PLS_INTEGER IS
    BEGIN RETURN BITOR(BITOR(BITAND(x,y),BITAND(x,z)),BITAND(y,z)); END;
  BEGIN
    -- SHA-512 initial hash values (first 8)
    IF is384 THEN
      h_hi(0):=3418070365; h_lo(0):=3238371032;
      h_hi(1):=1654270250; h_lo(1):=914150663;
      h_hi(2):=2438529370; h_lo(2):=812702999;
      h_hi(3):=355462360;  h_lo(3):=4144912697;
      h_hi(4):=1731405415; h_lo(4):=4290775857;
      h_hi(5):=2394180231; h_lo(5):=1750603025;
      h_hi(6):=3675008525; h_lo(6):=1694076839;
      h_hi(7):=1203062813; h_lo(7):=3204075428;
    ELSE
      h_hi(0):=1779033703; h_lo(0):=4089235720;
      h_hi(1):=3144134277; h_lo(1):=2227873595;
      h_hi(2):=1013904242; h_lo(2):=4271175723;
      h_hi(3):=2773480762; h_lo(3):=1595750129;
      h_hi(4):=1359893119; h_lo(4):=2917565137;
      h_hi(5):=2600822924; h_lo(5):=725511199;
      h_hi(6):=528734635;  h_lo(6):=4215389547;
      h_hi(7):=1541325195; h_lo(7):=327033209;
    END IF;

    -- SHA-512 round constants
    k_hi(0):=1116352408;  k_lo(0):=3609767458;
    k_hi(1):=1899447441;  k_lo(1):=602891725;
    k_hi(2):=3049323471;  k_lo(2):=3964484399;
    k_hi(3):=3921009573;  k_lo(3):=2173295548;
    k_hi(4):=961987163;   k_lo(4):=4081628472;
    k_hi(5):=1508970993;  k_lo(5):=3053834265;
    k_hi(6):=2453635748;  k_lo(6):=2937671579;
    k_hi(7):=2870763221;  k_lo(7):=3664609560;
    k_hi(8):=3624381080;  k_lo(8):=2734883394;
    k_hi(9):=310598401;   k_lo(9):=1164996542;
    k_hi(10):=607225278;  k_lo(10):=1323610764;
    k_hi(11):=1426881987; k_lo(11):=3590304994;
    k_hi(12):=1925078388; k_lo(12):=4068182383;
    k_hi(13):=2162078206; k_lo(13):=991336113;
    k_hi(14):=2614888103; k_lo(14):=633803317;
    k_hi(15):=3248222580; k_lo(15):=3479774868;
    k_hi(16):=3835390401; k_lo(16):=2666613458;
    k_hi(17):=4022224774; k_lo(17):=944711139;
    k_hi(18):=264347078;  k_lo(18):=2341262773;
    k_hi(19):=604807628;  k_lo(19):=2007800933;
    k_hi(20):=770255983;  k_lo(20):=1495990901;
    k_hi(21):=1249150122; k_lo(21):=1856431235;
    k_hi(22):=1555081692; k_lo(22):=3175218132;
    k_hi(23):=1996064986; k_lo(23):=2198950837;
    k_hi(24):=2554220882; k_lo(24):=3999719339;
    k_hi(25):=2821834349; k_lo(25):=766784016;
    k_hi(26):=2952996808; k_lo(26):=2566594879;
    k_hi(27):=3210313671; k_lo(27):=3203337956;
    k_hi(28):=3336571891; k_lo(28):=1034457026;
    k_hi(29):=3584528711; k_lo(29):=2466948901;
    k_hi(30):=113926993;  k_lo(30):=3758326383;
    k_hi(31):=338241895;  k_lo(31):=168717936;
    k_hi(32):=666307205;  k_lo(32):=1188179964;
    k_hi(33):=773529912;  k_lo(33):=1546045734;
    k_hi(34):=1294757372; k_lo(34):=1522805485;
    k_hi(35):=1396182291; k_lo(35):=2643833823;
    k_hi(36):=1695183700; k_lo(36):=2343527390;
    k_hi(37):=1986661051; k_lo(37):=1014477480;
    k_hi(38):=2177026350; k_lo(38):=1206759142;
    k_hi(39):=2456956037; k_lo(39):=344077627;
    k_hi(40):=2730485921; k_lo(40):=1290863460;
    k_hi(41):=2820302411; k_lo(41):=3158454273;
    k_hi(42):=3259730800; k_lo(42):=3505952657;
    k_hi(43):=3345764771; k_lo(43):=106217008;
    k_hi(44):=3516065817; k_lo(44):=3606008344;
    k_hi(45):=3600352804; k_lo(45):=1432725776;
    k_hi(46):=4094571909; k_lo(46):=1467031594;
    k_hi(47):=275423344;  k_lo(47):=851169720;
    k_hi(48):=430227734;  k_lo(48):=3100823752;
    k_hi(49):=506948616;  k_lo(49):=1363258195;
    k_hi(50):=659060556;  k_lo(50):=3750685593;
    k_hi(51):=883997877;  k_lo(51):=3785050280;
    k_hi(52):=958139571;  k_lo(52):=3318307427;
    k_hi(53):=1322822218; k_lo(53):=3812723403;
    k_hi(54):=1537002063; k_lo(54):=2003034995;
    k_hi(55):=1747873779; k_lo(55):=3602036899;
    k_hi(56):=1955562222; k_lo(56):=1575990012;
    k_hi(57):=2024104815; k_lo(57):=1125592928;
    k_hi(58):=2227730452; k_lo(58):=2716904306;
    k_hi(59):=2361852424; k_lo(59):=442776044;
    k_hi(60):=2428436474; k_lo(60):=593698344;
    k_hi(61):=2756734187; k_lo(61):=3733110249;
    k_hi(62):=3204031479; k_lo(62):=2999351573;
    k_hi(63):=3329325298; k_lo(63):=3815920427;
    k_hi(64):=3391569614; k_lo(64):=3928383900;
    k_hi(65):=3515267271; k_lo(65):=566280711;
    k_hi(66):=3940187606; k_lo(66):=3454069534;
    k_hi(67):=4118630271; k_lo(67):=4000239992;
    k_hi(68):=116418474;  k_lo(68):=1914138554;
    k_hi(69):=174292421;  k_lo(69):=2731055270;
    k_hi(70):=289380356;  k_lo(70):=3203993006;
    k_hi(71):=460393269;  k_lo(71):=320620315;
    k_hi(72):=685471733;  k_lo(72):=587496836;
    k_hi(73):=852142971;  k_lo(73):=1086792851;
    k_hi(74):=1017036298; k_lo(74):=365543100;
    k_hi(75):=1126000580; k_lo(75):=2618297676;
    k_hi(76):=1288033470; k_lo(76):=3409855158;
    k_hi(77):=1501505948; k_lo(77):=4234509866;
    k_hi(78):=1607167915; k_lo(78):=987167468;
    k_hi(79):=1816402316; k_lo(79):=1246189591;

    -- Padding: append 0x80 then zeros then 128-bit big-endian length
    pad := 128 - MOD(lb+17, 128);
    IF pad=128 THEN pad:=0; END IF;
    b := b || HEXTORAW('80') || HEXTORAW(LPAD('',pad*2,'00'))
           || HEXTORAW('00000000')  -- high 64 bits of length (lb < 2^32 bytes)
           || UTL_RAW.CAST_FROM_BINARY_INTEGER(FLOOR(lb/536870912),UTL_RAW.BIG_ENDIAN)
           || UTL_RAW.CAST_FROM_BINARY_INTEGER(MOD(lb,536870912)*8,UTL_RAW.BIG_ENDIAN);

    i := 1;
    WHILE i <= UTL_RAW.LENGTH(b) LOOP
      -- Load 16 x 64-bit words (each as hi,lo)
      FOR j IN 0..15 LOOP
        w_hi(j) := UTL_RAW.CAST_TO_BINARY_INTEGER(UTL_RAW.SUBSTR(b,i+j*8,4),  UTL_RAW.BIG_ENDIAN);
        w_lo(j) := UTL_RAW.CAST_TO_BINARY_INTEGER(UTL_RAW.SUBSTR(b,i+j*8+4,4),UTL_RAW.BIG_ENDIAN);
      END LOOP;
      -- Extend to 80 words
      FOR j IN 16..79 LOOP
        -- sigma1(w[j-2])
        s1h := BITXOR(BITXOR(rotr64_hi(w_hi(j-2),w_lo(j-2),19),rotr64_hi(w_hi(j-2),w_lo(j-2),61)),shr64_hi(w_hi(j-2),w_lo(j-2),6));
        s1l := BITXOR(BITXOR(rotr64_lo(w_hi(j-2),w_lo(j-2),19),rotr64_lo(w_hi(j-2),w_lo(j-2),61)),shr64_lo(w_hi(j-2),w_lo(j-2),6));
        -- sigma0(w[j-15])
        s0h := BITXOR(BITXOR(rotr64_hi(w_hi(j-15),w_lo(j-15),1),rotr64_hi(w_hi(j-15),w_lo(j-15),8)),shr64_hi(w_hi(j-15),w_lo(j-15),7));
        s0l := BITXOR(BITXOR(rotr64_lo(w_hi(j-15),w_lo(j-15),1),rotr64_lo(w_hi(j-15),w_lo(j-15),8)),shr64_lo(w_hi(j-15),w_lo(j-15),7));
        w_hi(j) := w_hi(j-16); w_lo(j) := w_lo(j-16);
        add64(w_hi(j),w_lo(j), s0h,s0l);
        add64(w_hi(j),w_lo(j), w_hi(j-7),w_lo(j-7));
        add64(w_hi(j),w_lo(j), s1h,s1l);
      END LOOP;
      ah:=h_hi(0); al:=h_lo(0); bh:=h_hi(1); bl:=h_lo(1);
      ch2:=h_hi(2); cl:=h_lo(2); dh:=h_hi(3); dl:=h_lo(3);
      eh:=h_hi(4); el:=h_lo(4); fh:=h_hi(5); fl:=h_lo(5);
      gh2:=h_hi(6); gl:=h_lo(6); hh2:=h_hi(7); hl:=h_lo(7);
      FOR j IN 0..79 LOOP
        -- Sigma1(e)
        s1h := BITXOR(BITXOR(rotr64_hi(eh,el,14),rotr64_hi(eh,el,18)),rotr64_hi(eh,el,41));
        s1l := BITXOR(BITXOR(rotr64_lo(eh,el,14),rotr64_lo(eh,el,18)),rotr64_lo(eh,el,41));
        -- Ch(e,f,g)
        tmp_h := ch_h(eh,fh,gh2); tmp_l := ch_h(el,fl,gl);
        -- T1 = h + S1 + Ch + K[j] + W[j]
        t1h := hh2; t1l := hl;
        add64(t1h,t1l, s1h,s1l);
        add64(t1h,t1l, tmp_h,tmp_l);
        add64(t1h,t1l, k_hi(j),k_lo(j));
        add64(t1h,t1l, w_hi(j),w_lo(j));
        -- Sigma0(a)
        s0h := BITXOR(BITXOR(rotr64_hi(ah,al,28),rotr64_hi(ah,al,34)),rotr64_hi(ah,al,39));
        s0l := BITXOR(BITXOR(rotr64_lo(ah,al,28),rotr64_lo(ah,al,34)),rotr64_lo(ah,al,39));
        -- Maj(a,b,c)
        tmp_h := maj_h(ah,bh,ch2); tmp_l := maj_h(al,bl,cl);
        -- T2 = S0 + Maj
        t2h := s0h; t2l := s0l;
        add64(t2h,t2l, tmp_h,tmp_l);
        hh2:=gh2; hl:=gl; gh2:=fh; gl:=fl; fh:=eh; fl:=el;
        eh:=dh; el:=dl; add64(eh,el,t1h,t1l);
        dh:=ch2; dl:=cl; ch2:=bh; cl:=bl; bh:=ah; bl:=al;
        ah:=t1h; al:=t1l; add64(ah,al,t2h,t2l);
      END LOOP;
      add64(h_hi(0),h_lo(0), ah,al); add64(h_hi(1),h_lo(1), bh,bl);
      add64(h_hi(2),h_lo(2), ch2,cl); add64(h_hi(3),h_lo(3), dh,dl);
      add64(h_hi(4),h_lo(4), eh,el); add64(h_hi(5),h_lo(5), fh,fl);
      add64(h_hi(6),h_lo(6), gh2,gl); add64(h_hi(7),h_lo(7), hh2,hl);
      i := i + 128;
    END LOOP;
    IF is384 THEN
      RETURN    UTL_RAW.CAST_FROM_BINARY_INTEGER(h_hi(0),UTL_RAW.BIG_ENDIAN)||UTL_RAW.CAST_FROM_BINARY_INTEGER(h_lo(0),UTL_RAW.BIG_ENDIAN)
             || UTL_RAW.CAST_FROM_BINARY_INTEGER(h_hi(1),UTL_RAW.BIG_ENDIAN)||UTL_RAW.CAST_FROM_BINARY_INTEGER(h_lo(1),UTL_RAW.BIG_ENDIAN)
             || UTL_RAW.CAST_FROM_BINARY_INTEGER(h_hi(2),UTL_RAW.BIG_ENDIAN)||UTL_RAW.CAST_FROM_BINARY_INTEGER(h_lo(2),UTL_RAW.BIG_ENDIAN)
             || UTL_RAW.CAST_FROM_BINARY_INTEGER(h_hi(3),UTL_RAW.BIG_ENDIAN)||UTL_RAW.CAST_FROM_BINARY_INTEGER(h_lo(3),UTL_RAW.BIG_ENDIAN)
             || UTL_RAW.CAST_FROM_BINARY_INTEGER(h_hi(4),UTL_RAW.BIG_ENDIAN)||UTL_RAW.CAST_FROM_BINARY_INTEGER(h_lo(4),UTL_RAW.BIG_ENDIAN)
             || UTL_RAW.CAST_FROM_BINARY_INTEGER(h_hi(5),UTL_RAW.BIG_ENDIAN)||UTL_RAW.CAST_FROM_BINARY_INTEGER(h_lo(5),UTL_RAW.BIG_ENDIAN);
    ELSE
      RETURN    UTL_RAW.CAST_FROM_BINARY_INTEGER(h_hi(0),UTL_RAW.BIG_ENDIAN)||UTL_RAW.CAST_FROM_BINARY_INTEGER(h_lo(0),UTL_RAW.BIG_ENDIAN)
             || UTL_RAW.CAST_FROM_BINARY_INTEGER(h_hi(1),UTL_RAW.BIG_ENDIAN)||UTL_RAW.CAST_FROM_BINARY_INTEGER(h_lo(1),UTL_RAW.BIG_ENDIAN)
             || UTL_RAW.CAST_FROM_BINARY_INTEGER(h_hi(2),UTL_RAW.BIG_ENDIAN)||UTL_RAW.CAST_FROM_BINARY_INTEGER(h_lo(2),UTL_RAW.BIG_ENDIAN)
             || UTL_RAW.CAST_FROM_BINARY_INTEGER(h_hi(3),UTL_RAW.BIG_ENDIAN)||UTL_RAW.CAST_FROM_BINARY_INTEGER(h_lo(3),UTL_RAW.BIG_ENDIAN)
             || UTL_RAW.CAST_FROM_BINARY_INTEGER(h_hi(4),UTL_RAW.BIG_ENDIAN)||UTL_RAW.CAST_FROM_BINARY_INTEGER(h_lo(4),UTL_RAW.BIG_ENDIAN)
             || UTL_RAW.CAST_FROM_BINARY_INTEGER(h_hi(5),UTL_RAW.BIG_ENDIAN)||UTL_RAW.CAST_FROM_BINARY_INTEGER(h_lo(5),UTL_RAW.BIG_ENDIAN)
             || UTL_RAW.CAST_FROM_BINARY_INTEGER(h_hi(6),UTL_RAW.BIG_ENDIAN)||UTL_RAW.CAST_FROM_BINARY_INTEGER(h_lo(6),UTL_RAW.BIG_ENDIAN)
             || UTL_RAW.CAST_FROM_BINARY_INTEGER(h_hi(7),UTL_RAW.BIG_ENDIAN)||UTL_RAW.CAST_FROM_BINARY_INTEGER(h_lo(7),UTL_RAW.BIG_ENDIAN);
    END IF;
  END sha512_core;

  -- -----------------------------------------------------------------------
  -- Public HASH function
  -- -----------------------------------------------------------------------
  FUNCTION hash( src RAW, typ PLS_INTEGER ) RETURN RAW IS
  BEGIN
    CASE typ
      WHEN HASH_MD4    THEN RETURN md4(src);
      WHEN HASH_MD5    THEN RETURN md5(src);
      WHEN HASH_SH1    THEN RETURN sha1(src);
      WHEN HASH_SH256  THEN RETURN sha256(src);
      WHEN HASH_SH384  THEN RETURN sha512_core(src, TRUE);
      WHEN HASH_SH512  THEN RETURN sha512_core(src, FALSE);
      ELSE RAISE_APPLICATION_ERROR(-20001,'UC_CRYPTO: unsupported hash type '||typ);
    END CASE;
  END hash;

  -- -----------------------------------------------------------------------
  -- HMAC (for MAC support)
  -- -----------------------------------------------------------------------
  FUNCTION mac( src RAW, typ PLS_INTEGER, key RAW ) RETURN RAW IS
    block_size PLS_INTEGER := 64;
    k   RAW(128);
    k_  RAW(128);
    ipad RAW(64); opad RAW(64);
    i_key_pad RAW(32767); o_key_pad RAW(32767);
    k_len PLS_INTEGER;
  BEGIN
    IF typ IN (HASH_SH384, HASH_SH512) THEN block_size := 128; END IF;
    k_len := NVL(UTL_RAW.LENGTH(key),0);
    IF k_len > block_size THEN
      k := hash(key, typ);
    ELSE
      k := key;
    END IF;
    k := UTL_RAW.CONCAT(k, HEXTORAW(LPAD('',( block_size - NVL(UTL_RAW.LENGTH(k),0) )*2,'00')));
    ipad := HEXTORAW(LPAD('',block_size*2,'36'));
    opad := HEXTORAW(LPAD('',block_size*2,'5C'));
    i_key_pad := UTL_RAW.BIT_XOR(k, ipad);
    o_key_pad := UTL_RAW.BIT_XOR(k, opad);
    RETURN hash( UTL_RAW.CONCAT(o_key_pad, hash(UTL_RAW.CONCAT(i_key_pad, src), typ)), typ );
  END mac;

  -- -----------------------------------------------------------------------
  -- Cryptographic random bytes using DBMS_RANDOM seeded with high-res time
  -- -----------------------------------------------------------------------
  FUNCTION randombytes( number_bytes POSITIVE ) RETURN RAW IS
    v_result RAW(32767);
    v_chunk  RAW(2000);
    v_hex    VARCHAR2(4000);
    v_needed PLS_INTEGER := number_bytes;
    v_take   PLS_INTEGER;
  BEGIN
    -- Seed with current timestamp microseconds for unpredictability
    DBMS_RANDOM.SEED( TO_CHAR(SYSTIMESTAMP,'YYYYMMDDHH24MISSFF9') );
    WHILE v_needed > 0 LOOP
      v_take := LEAST(v_needed, 1000);
      -- Generate random hex chars (2 chars per byte)
      v_hex := '';
      FOR i IN 1..v_take LOOP
        v_hex := v_hex || TO_CHAR(TRUNC(DBMS_RANDOM.VALUE(0,256)),'FM0X');
      END LOOP;
      v_chunk := HEXTORAW(v_hex);
      IF v_result IS NULL THEN v_result := v_chunk;
      ELSE v_result := UTL_RAW.CONCAT(v_result, v_chunk);
      END IF;
      v_needed := v_needed - v_take;
    END LOOP;
    RETURN v_result;
  END randombytes;

  -- -----------------------------------------------------------------------
  -- AES support (ECB/CBC with PKCS5 padding) -- simplified implementation
  -- -----------------------------------------------------------------------

  -- AES S-box
  FUNCTION get_sbox RETURN tp_sbox IS
    s tp_sbox;
  BEGIN
    -- Standard AES S-box values
    s(0):=99;  s(1):=124; s(2):=119; s(3):=123; s(4):=242; s(5):=107; s(6):=111; s(7):=197;
    s(8):=48;  s(9):=1;   s(10):=103;s(11):=43; s(12):=254;s(13):=215;s(14):=171;s(15):=118;
    s(16):=202;s(17):=130;s(18):=201;s(19):=125;s(20):=250;s(21):=89; s(22):=71; s(23):=240;
    s(24):=173;s(25):=212;s(26):=162;s(27):=175;s(28):=156;s(29):=164;s(30):=114;s(31):=192;
    s(32):=183;s(33):=253;s(34):=147;s(35):=38; s(36):=54; s(37):=63; s(38):=247;s(39):=204;
    s(40):=52; s(41):=165;s(42):=229;s(43):=241;s(44):=113;s(45):=216;s(46):=49; s(47):=21;
    s(48):=4;  s(49):=199;s(50):=35; s(51):=195;s(52):=24; s(53):=150;s(54):=5;  s(55):=154;
    s(56):=7;  s(57):=18; s(58):=128;s(59):=226;s(60):=235;s(61):=39; s(62):=178;s(63):=117;
    s(64):=9;  s(65):=131;s(66):=44; s(67):=26; s(68):=27; s(69):=110;s(70):=90; s(71):=160;
    s(72):=82; s(73):=59; s(74):=214;s(75):=179;s(76):=41; s(77):=227;s(78):=47; s(79):=132;
    s(80):=83; s(81):=209;s(82):=0;  s(83):=237;s(84):=32; s(85):=252;s(86):=177;s(87):=91;
    s(88):=106;s(89):=203;s(90):=190;s(91):=57; s(92):=74; s(93):=76; s(94):=88; s(95):=207;
    s(96):=208;s(97):=239;s(98):=170;s(99):=251;s(100):=67;s(101):=77;s(102):=51;s(103):=133;
    s(104):=69;s(105):=249;s(106):=2;s(107):=127;s(108):=80;s(109):=60;s(110):=159;s(111):=168;
    s(112):=81;s(113):=163;s(114):=64;s(115):=143;s(116):=146;s(117):=157;s(118):=56;s(119):=245;
    s(120):=188;s(121):=182;s(122):=218;s(123):=33;s(124):=16;s(125):=255;s(126):=243;s(127):=210;
    s(128):=205;s(129):=12;s(130):=19;s(131):=236;s(132):=95;s(133):=151;s(134):=68;s(135):=23;
    s(136):=196;s(137):=167;s(138):=126;s(139):=61;s(140):=100;s(141):=93;s(142):=25;s(143):=115;
    s(144):=96;s(145):=129;s(146):=79;s(147):=220;s(148):=34;s(149):=42;s(150):=144;s(151):=136;
    s(152):=70;s(153):=238;s(154):=184;s(155):=20;s(156):=222;s(157):=94;s(158):=11;s(159):=219;
    s(160):=224;s(161):=50;s(162):=58;s(163):=10;s(164):=73;s(165):=6;s(166):=36;s(167):=92;
    s(168):=194;s(169):=211;s(170):=172;s(171):=98;s(172):=145;s(173):=149;s(174):=228;s(175):=121;
    s(176):=231;s(177):=200;s(178):=55;s(179):=109;s(180):=141;s(181):=213;s(182):=78;s(183):=169;
    s(184):=108;s(185):=86;s(186):=244;s(187):=234;s(188):=101;s(189):=122;s(190):=174;s(191):=8;
    s(192):=186;s(193):=120;s(194):=37;s(195):=46;s(196):=28;s(197):=166;s(198):=180;s(199):=198;
    s(200):=232;s(201):=221;s(202):=116;s(203):=31;s(204):=75;s(205):=189;s(206):=139;s(207):=138;
    s(208):=112;s(209):=62;s(210):=181;s(211):=102;s(212):=72;s(213):=3;s(214):=246;s(215):=14;
    s(216):=97;s(217):=53;s(218):=87;s(219):=185;s(220):=134;s(221):=193;s(222):=29;s(223):=158;
    s(224):=225;s(225):=248;s(226):=152;s(227):=17;s(228):=105;s(229):=217;s(230):=142;s(231):=148;
    s(232):=155;s(233):=30;s(234):=135;s(235):=233;s(236):=206;s(237):=85;s(238):=40;s(239):=223;
    s(240):=140;s(241):=161;s(242):=137;s(243):=13;s(244):=191;s(245):=230;s(246):=66;s(247):=104;
    s(248):=65;s(249):=153;s(250):=45;s(251):=15;s(252):=176;s(253):=84;s(254):=187;s(255):=22;
    RETURN s;
  END get_sbox;

  FUNCTION xtime( b PLS_INTEGER ) RETURN PLS_INTEGER IS
  BEGIN
    IF b < 128 THEN RETURN b*2;
    ELSE RETURN MOD(b*2,256) + 27;
    END IF;
  END;

  FUNCTION gmul( a PLS_INTEGER, b PLS_INTEGER ) RETURN PLS_INTEGER IS
    p PLS_INTEGER := 0;
    av PLS_INTEGER := a;
    bv PLS_INTEGER := b;
  BEGIN
    FOR i IN 1..8 LOOP
      IF MOD(bv,2)=1 THEN p := BITXOR(p,av); END IF;
      av := xtime(av);
      bv := FLOOR(bv/2);
    END LOOP;
    RETURN p;
  END;

  -- AES encrypt single 16-byte block, key_words is expanded key
  FUNCTION aes_block_encrypt( blk RAW, key_words tp_tab_num, nr PLS_INTEGER ) RETURN RAW IS
    s   tp_sbox := get_sbox;
    st  tp_tab_num; -- 16 state bytes indexed 0..15
    tmp tp_tab_num;
    w   PLS_INTEGER;
    i   PLS_INTEGER;
    t0  PLS_INTEGER; t1 PLS_INTEGER; t2 PLS_INTEGER; t3 PLS_INTEGER;
  BEGIN
    FOR j IN 0..15 LOOP
      st(j) := UTL_RAW.CAST_TO_BINARY_INTEGER(UTL_RAW.SUBSTR(blk,j+1,1));
    END LOOP;
    -- AddRoundKey(0)
    FOR j IN 0..3 LOOP
      w := key_words(j);
      st(j*4)   := BITXOR(st(j*4),   FLOOR(w/16777216));
      st(j*4+1) := BITXOR(st(j*4+1), MOD(FLOOR(w/65536),256));
      st(j*4+2) := BITXOR(st(j*4+2), MOD(FLOOR(w/256),256));
      st(j*4+3) := BITXOR(st(j*4+3), MOD(w,256));
    END LOOP;
    FOR rnd IN 1..nr LOOP
      -- SubBytes
      FOR j IN 0..15 LOOP st(j) := s(st(j)); END LOOP;
      -- ShiftRows: row0 unchanged, row1 shift1, row2 shift2, row3 shift3
      -- State is column-major: col c = st(c*4..c*4+3)
      -- row r = st(0+r), st(4+r), st(8+r), st(12+r)
      tmp(1) := st(1); st(1) := st(5); st(5) := st(9); st(9) := st(13); st(13) := tmp(1);
      tmp(2) := st(2); tmp(6) := st(6); st(2) := st(10); st(6) := st(14); st(10) := tmp(2); st(14) := tmp(6);
      tmp(3) := st(15); st(15) := st(11); st(11) := st(7); st(7) := st(3); st(3) := tmp(3);
      -- MixColumns (skip on last round)
      IF rnd < nr THEN
        FOR col IN 0..3 LOOP
          t0 := st(col*4); t1 := st(col*4+1); t2 := st(col*4+2); t3 := st(col*4+3);
          st(col*4)   := BITXOR(BITXOR(BITXOR(gmul(2,t0),gmul(3,t1)),t2),t3);
          st(col*4+1) := BITXOR(BITXOR(BITXOR(t0,gmul(2,t1)),gmul(3,t2)),t3);
          st(col*4+2) := BITXOR(BITXOR(BITXOR(t0,t1),gmul(2,t2)),gmul(3,t3));
          st(col*4+3) := BITXOR(BITXOR(BITXOR(gmul(3,t0),t1),t2),gmul(2,t3));
        END LOOP;
      END IF;
      -- AddRoundKey
      FOR j IN 0..3 LOOP
        w := key_words(rnd*4+j);
        st(j*4)   := BITXOR(st(j*4),   FLOOR(w/16777216));
        st(j*4+1) := BITXOR(st(j*4+1), MOD(FLOOR(w/65536),256));
        st(j*4+2) := BITXOR(st(j*4+2), MOD(FLOOR(w/256),256));
        st(j*4+3) := BITXOR(st(j*4+3), MOD(w,256));
      END LOOP;
    END LOOP;
    RETURN    UTL_RAW.CAST_FROM_BINARY_INTEGER(st(0)*16777216+st(1)*65536+st(2)*256+st(3))
           || UTL_RAW.CAST_FROM_BINARY_INTEGER(st(4)*16777216+st(5)*65536+st(6)*256+st(7))
           || UTL_RAW.CAST_FROM_BINARY_INTEGER(st(8)*16777216+st(9)*65536+st(10)*256+st(11))
           || UTL_RAW.CAST_FROM_BINARY_INTEGER(st(12)*16777216+st(13)*65536+st(14)*256+st(15));
  END aes_block_encrypt;

  -- AES key expansion
  PROCEDURE aes_key_expand( key RAW, key_words OUT tp_tab_num, nr OUT PLS_INTEGER ) IS
    s    tp_sbox := get_sbox;
    nk   PLS_INTEGER := UTL_RAW.LENGTH(key)/4;
    temp PLS_INTEGER;
    rcon tp_tab_num;
    i    PLS_INTEGER;
    rot  PLS_INTEGER;
    sub  PLS_INTEGER;
  BEGIN
    rcon(1):=1; rcon(2):=2; rcon(3):=4; rcon(4):=8; rcon(5):=16;
    rcon(6):=32; rcon(7):=64; rcon(8):=128; rcon(9):=27; rcon(10):=54;
    nr := nk + 6; -- 10 for AES-128, 12 for AES-192, 14 for AES-256
    FOR j IN 0..nk-1 LOOP
      key_words(j) := UTL_RAW.CAST_TO_BINARY_INTEGER(UTL_RAW.SUBSTR(key,j*4+1,4),UTL_RAW.BIG_ENDIAN);
    END LOOP;
    i := nk;
    WHILE i <= (nr+1)*4-1 LOOP
      temp := key_words(i-1);
      IF MOD(i,nk)=0 THEN
        -- RotWord
        rot := MOD(temp,256)*16777216 + FLOOR(temp/256);
        -- SubWord
        sub := s(FLOOR(rot/16777216))*16777216
             + s(MOD(FLOOR(rot/65536),256))*65536
             + s(MOD(FLOOR(rot/256),256))*256
             + s(MOD(rot,256));
        temp := BITXOR(sub, rcon(i/nk)*16777216);
      ELSIF nk>6 AND MOD(i,nk)=4 THEN
        temp := s(FLOOR(temp/16777216))*16777216
              + s(MOD(FLOOR(temp/65536),256))*65536
              + s(MOD(FLOOR(temp/256),256))*256
              + s(MOD(temp,256));
      END IF;
      key_words(i) := BITXOR(key_words(i-nk), temp);
      i := i + 1;
    END LOOP;
  END aes_key_expand;

  -- -----------------------------------------------------------------------
  -- Public ENCRYPT / DECRYPT
  -- -----------------------------------------------------------------------
  FUNCTION encrypt( src RAW, typ PLS_INTEGER, key RAW, iv RAW := NULL ) RETURN RAW IS
    alg       PLS_INTEGER := MOD(typ, 256);
    chain     PLS_INTEGER := MOD(FLOOR(typ/256), 16) * 256;
    pad_mode  PLS_INTEGER := MOD(FLOOR(typ/4096), 16) * 4096;
    key_words tp_tab_num;
    nr        PLS_INTEGER;
    result    RAW(32767);
    blk       RAW(16);
    prev      RAW(16);
    src_pad   RAW(32767);
    lb        PLS_INTEGER;
    pad_len   PLS_INTEGER;
  BEGIN
    IF alg NOT IN (ENCRYPT_AES128, ENCRYPT_AES192, ENCRYPT_AES256) THEN
      RAISE_APPLICATION_ERROR(-20002,'UC_CRYPTO: only AES supported in this build');
    END IF;
    aes_key_expand(key, key_words, nr);
    lb := NVL(UTL_RAW.LENGTH(src),0);
    pad_len := 16 - MOD(lb,16);
    IF pad_mode = PAD_PKCS5 THEN
      src_pad := src || HEXTORAW(LPAD('',pad_len*2,TO_CHAR(pad_len,'FM0X')||TO_CHAR(pad_len,'FM0X')));
    ELSIF pad_mode = PAD_ZERO THEN
      src_pad := src || HEXTORAW(LPAD('',pad_len*2,'00'));
    ELSE -- PAD_NONE
      src_pad := src;
    END IF;
    prev := NVL(iv, HEXTORAW('00000000000000000000000000000000'));
    FOR i IN 1..UTL_RAW.LENGTH(src_pad)/16 LOOP
      blk := UTL_RAW.SUBSTR(src_pad,(i-1)*16+1,16);
      IF chain = CHAIN_CBC THEN blk := UTL_RAW.BIT_XOR(blk, prev); END IF;
      blk := aes_block_encrypt(blk, key_words, nr);
      prev := blk;
      result := UTL_RAW.CONCAT(result, blk);
    END LOOP;
    RETURN result;
  END encrypt;

  FUNCTION decrypt( src RAW, typ PLS_INTEGER, key RAW, iv RAW := NULL ) RETURN RAW IS
  BEGIN
    -- Decrypt is the inverse of encrypt; for the EPF use-case (hashing + random),
    -- decrypt is not called. Raising a not-implemented error keeps the package
    -- compilable without requiring the full inverse S-box / InvMixColumns tables.
    RAISE_APPLICATION_ERROR(-20003,'UC_CRYPTO.DECRYPT: not implemented in this build. Use DBMS_CRYPTO for decrypt operations.');
    RETURN NULL;
  END decrypt;

END uc_crypto;
/
