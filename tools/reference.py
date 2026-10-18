"""Integer contract model; no RTL work is delegated to this file."""
C = [
 [5793]*8,
 [8035,6811,4551,1598,-1598,-4551,-6811,-8035],
 [7568,3135,-3135,-7568,-7568,-3135,3135,7568],
 [6811,-1598,-8035,-4551,4551,8035,1598,-6811],
 [5793,-5793,-5793,5793,5793,-5793,-5793,5793],
 [4551,-8035,1598,6811,-6811,-1598,8035,-4551],
 [3135,-7568,7568,-3135,-3135,7568,-7568,3135],
 [1598,-4551,6811,-8035,8035,-6811,4551,-1598]]
ZIGZAG = [0,1,8,16,9,2,3,10,17,24,32,25,18,11,4,5,12,19,26,33,40,48,41,34,27,20,13,6,7,14,21,28,35,42,49,56,57,50,43,36,29,22,15,23,30,37,44,51,58,59,52,45,38,31,39,46,53,60,61,54,47,55,62,63]
def r14(x): return (1 if x >= 0 else -1)*((abs(x)+8192)//16384)
def transform(block, decode=False):
    x = [block[i:i+8] for i in range(0,64,8)]
    if not decode: x = [[a-128 for a in row] for row in x]
    mat = list(map(list,zip(*C))) if decode else C
    t = [[r14(sum(mat[k][n]*x[r][n] for n in range(8))) for k in range(8)] for r in range(8)]
    y = [[r14(sum(mat[k][n]*t[n][c] for n in range(8))) for c in range(8)] for k in range(8)]
    if decode: y = [[max(0,min(255,a+128)) for a in row] for row in y]
    return sum(y,[])
def quant(x,q): return (1 if x >= 0 else -1)*((2*abs(x)+q)//(2*q))
def huffman(counts,symbols):
    if len(counts)!=16 or any(n<0 or n>255 for n in counts) or sum(counts)!=len(symbols) or len(symbols)>256 or any(s<0 or s>255 for s in symbols):
        raise ValueError('invalid Huffman table dimensions')
    enc=[0]*256; dec=[0]*320; code=0; offset=0
    for l,count in enumerate(counts,1):
        if count and code+count-1 >= (1<<l)-1:raise ValueError('overallocated or all-one Huffman code')
        dec[4*(l-1):4*l]=[code,code+count-1 if count else 0,(offset if count else offset&255),count]
        for i in range(count):
            enc[symbols[offset+i]]=(1<<21)|(l<<16)|(code+i)
        code=(code+count)<<1; offset+=count
    dec[64:64+len(symbols)]=symbols
    return enc,dec
def encode_scan(blocks, qtables, dc, ac):
    bits=[];pred=[0,0,0];quantized=[]
    def put(code,n): bits.extend((code>>k)&1 for k in range(n-1,-1,-1))
    def token(symbol,value,table):
        entry=table[symbol];n=abs(value).bit_length()
        put(entry&65535,(entry>>16)&31)
        if n: put(value if value>=0 else ((1<<n)-1)^abs(value),n)
    for comp,pixels in blocks:
        coeff=[quant(v,q) for v,q in zip(transform(pixels),qtables[comp])];quantized.append((comp,coeff))
        d=coeff[0]-pred[comp];pred[comp]=coeff[0];token(abs(d).bit_length(),d,dc)
        run=0
        for index in range(1,64):
            v=coeff[ZIGZAG[index]]
            if not v: run+=1
            else:
                while run>=16:token(0xf0,0,ac);run-=16
                token((run<<4)|abs(v).bit_length(),v,ac);run=0
        if run:token(0,0,ac)
    bits.extend([1]*((-len(bits))%8));scan=bytearray()
    for i in range(0,len(bits),8):
        v=sum(b<<(7-k) for k,b in enumerate(bits[i:i+8]));scan.append(v)
        if v==255:scan.append(0)
    return bytes(scan),quantized

def frame_blocks(planes,width,height,fmt):
    hs=1 if fmt==0 else 2;vs=2 if fmt==2 else 1
    dims=[(width,height)]+[((width+hs-1)//hs,(height+vs-1)//vs)]*2
    for my in range((height+8*vs-1)//(8*vs)):
        for mx in range((width+8*hs-1)//(8*hs)):
            for comp,(w,h) in enumerate(dims):
                for dy in range(vs if comp==0 else 1):
                    for dx in range(hs if comp==0 else 1):
                        bx=mx*8*(hs if comp==0 else 1)+dx*8;by=my*8*(vs if comp==0 else 1)+dy*8
                        yield comp,[planes[comp][min(by+y,h-1)*w+min(bx+x,w-1)] for y in range(8) for x in range(8)]

def reconstructed(quantized,width,height,fmt,qtables):
    hs=1 if fmt==0 else 2;vs=2 if fmt==2 else 1
    dims=[(width,height)]+[((width+hs-1)//hs,(height+vs-1)//vs)]*2
    out=[bytearray(w*h) for w,h in dims];it=iter(quantized)
    for my in range((height+8*vs-1)//(8*vs)):
        for mx in range((width+8*hs-1)//(8*hs)):
            for comp,(w,h) in enumerate(dims):
                for dy in range(vs if comp==0 else 1):
                    for dx in range(hs if comp==0 else 1):
                        actual,coeff=next(it);assert actual==comp
                        pixels=transform([v*q for v,q in zip(coeff,qtables[comp])],True)
                        bx=mx*8*(hs if comp==0 else 1)+dx*8;by=my*8*(vs if comp==0 else 1)+dy*8
                        for y in range(8):
                            for x in range(8):
                                if by+y<h and bx+x<w:out[comp][(by+y)*w+bx+x]=pixels[y*8+x]
    return out
