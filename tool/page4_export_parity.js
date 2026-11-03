// Run with playwright-cli run-code --filename=tool/page4_export_parity.js.
// The loopback preview server receives synthetic-only review artifacts.
async (page) => {
  return await page.evaluate(async () => {
    async function compare(format) {
    const pdfjs = await import('/vendor/pdfjs/pdf.min.mjs');
    pdfjs.GlobalWorkerOptions.workerSrc = '/vendor/pdfjs/pdf.worker.min.mjs';
    const pdf = await pdfjs.getDocument({data: new Uint8Array(await (await fetch(`/review/${format}.pdf`)).arrayBuffer())}).promise;
    const pages = [];
    for (let n = 1; n <= pdf.numPages; n++) {
      const page = await pdf.getPage(n);
      const viewport = page.getViewport({scale: 2});
      const canvas = document.createElement('canvas');
      canvas.width = Math.floor(viewport.width); canvas.height = Math.floor(viewport.height);
      await page.render({canvasContext: canvas.getContext('2d'),viewport}).promise;
      pages.push(canvas);
    }
    const reference = document.createElement('canvas');
    reference.width = Math.max(...pages.map(p=>p.width));
    reference.height = pages.reduce((s,p)=>s+p.height,0)+(pages.length-1)*24;
    const ctx = reference.getContext('2d');
    ctx.fillStyle = '#e8e8e8'; ctx.fillRect(0,0,reference.width,reference.height);
    let y = 0;
    for (const p of pages) {ctx.drawImage(p,(reference.width-p.width)/2,y);y+=p.height+24;}
    const actual = await createImageBitmap(await (await fetch(`/review/${format}.png`)).blob());
    const actualCanvas = document.createElement('canvas');
    actualCanvas.width=actual.width;actualCanvas.height=actual.height;
    actualCanvas.getContext('2d').drawImage(actual,0,0);
    if(actual.width!==reference.width||actual.height!==reference.height) throw Error('Page dimensions differ');
    const a=ctx.getImageData(0,0,reference.width,reference.height).data;
    const b=actualCanvas.getContext('2d').getImageData(0,0,actual.width,actual.height).data;
    let changed=0,maxError=0,total=0;
    for(let i=0;i<a.length;i+=4){let changedPixel=false;for(let j=0;j<4;j++){
      const error=Math.abs(a[i+j]-b[i+j]);total+=error;maxError=Math.max(maxError,error);changedPixel ||= error>2;
    }if(changedPixel)changed++;}
    const result={format,pages:pdf.numPages,width:actual.width,height:actual.height,
      differingPixelsOver2:changed,maxChannelError:maxError,meanChannelError:total/a.length};
    const referenceBlob=await new Promise(resolve=>reference.toBlob(resolve,'image/png'));
    await fetch(`/__review/${format}-reference.png`,{method:'POST',body:referenceBlob});
    await fetch(`/__review/${format}-parity.json`,{method:'POST',body:JSON.stringify(result,null,2)});
    await pdf.cleanup();
    if(changed>0)throw Error(JSON.stringify(result));
    return result;
    }
    const results=[];
    for(const format of ["standard","wide","tall"]) results.push(await compare(format));
    return results;
  });
}
