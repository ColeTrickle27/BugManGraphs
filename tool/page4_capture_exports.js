// Headless, isolated browser only. All documents and writes are synthetic/loopback.
async (page) => {
  await page.setViewportSize({width:1400,height:900});
  const results=[];
  for(const format of ['standard','wide','tall']) {
    await page.goto(`http://127.0.0.1:8794/?exportReview=1&fixture=${format}`);
    await page.getByRole('button',{name:'Enable accessibility'}).waitFor();
    await page.getByRole('button',{name:'Enable accessibility'}).evaluate(el=>el.click());
    await page.getByRole('button',{name:'File actions',exact:true}).waitFor();
    await page.getByLabel('Fit drawing',{exact:true}).click();
    await page.mouse.move(1360,45);
    await page.screenshot({path:`output/playwright/${format}-desktop.png`,scale:'css'});
    for(const extension of ['pdf','png']) {
      await page.getByRole('button',{name:'File actions',exact:true}).click();
      const responsePromise=page.waitForResponse(r=>r.url().endsWith(`/__review/${format}.${extension}`),{timeout:60000});
      await page.getByRole('menuitem',{name:`Export ${extension.toUpperCase()}`,exact:true}).click();
      const response=await responsePromise;
      results.push({format,extension,status:response.status()});
      await response.finished();
      await page.waitForTimeout(100);
    }
  }
  return results;
}
