/* One input in flight, transferred outputs, no whole-pack accumulation. */
importScripts('vendor/fflate-0.8.2.js');
let decoder;
self.onmessage = ({data}) => {
  try {
    if (data.init) {
      decoder = new fflate.Gunzip();
      self.postMessage({ready:true});
      return;
    }
    const chunks=[];
    decoder.ondata = bytes => {if (bytes.length) chunks.push(bytes);};
    decoder.push(data.input,data.final);
    self.postMessage({chunks},chunks.map(bytes=>bytes.buffer));
    if (data.final) decoder=null;
  } catch (error) {self.postMessage({error:String(error.message || error)});}
};
