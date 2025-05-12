use std::fs::File;
use std::io::Read;

mod flac {
    #[derive(Debug)]
    pub enum MetadataBlockType {
        StreamInfo,
        Padding,
        Application,
        SeekTable,
        VorbisComment,
        CueSheet,
        Picture,
    }

    #[derive(Debug)]
    pub struct MetadataBlockHeader {
        pub last: bool,
        pub ty: MetadataBlockType,
        pub length: u32,
    }

    #[derive(Debug)]
    pub struct MetadataBlock {
        pub header: MetadataBlockHeader,
        pub data: Vec<u8>,
    }

    #[derive(Debug)]
    struct VorbisComment {
        vendor_string: String,
        user_comment_list: Vec<UserComment>,
    }

    #[derive(Debug)]
    struct UserComment {
        key: String,
        value: String,
    }
}

fn main() -> std::io::Result<()> {
    let mut f = File::open("/home/chris/03 - A Milli.flac")?;
    let mut buf = vec![0; 1024];
    let hdr = f.read(&mut buf[0..4])?;
    assert!(buf[0..4] == [0x66, 0x4c, 0x61, 0x43]);

    loop {
        f.read(&mut buf[0..4])?;
        let ty = match buf[0] & 0x7F {
            0 => flac::MetadataBlockType::StreamInfo,
            1 => flac::MetadataBlockType::Padding,
            2 => flac::MetadataBlockType::Application,
            3 => flac::MetadataBlockType::SeekTable,
            4 => flac::MetadataBlockType::VorbisComment,
            5 => flac::MetadataBlockType::CueSheet,
            6 => flac::MetadataBlockType::Picture,
            _ => unreachable!(),
        };

        let header = flac::MetadataBlockHeader {
            last: (buf[0] >> 7) == 1,
            ty,
            length: u32::from_be_bytes([0, buf[1], buf[2], buf[3]]),
        };

        f.read_exact(&mut buf[..header.length as usize])?;
        let data = buf[..header.length as usize].to_vec();

        let block = flac::MetadataBlock { header, data };

        dbg!(&block.header);

        if let flac::MetadataBlockType::VorbisComment = block.header.ty {
            let data = &block.data;
            let vendor_length = u32::from_le_bytes([data[0], data[1], data[2], data[3]]) as usize;

            let data = &data[4..];

            let vendor_string = String::from_utf8_lossy(&block.data[..vendor_length + 4]);

            dbg!(vendor_string);

            let data = &data[vendor_length + 4..];

            let user_comment_list_len =
                u32::from_le_bytes([data[0], data[1], data[2], data[3]]) as usize;

            dbg!(user_comment_list_len);

            let mut data = &data[4..];

            for _ in 0..user_comment_list_len {
                let comment_len = u32::from_le_bytes([data[0], data[1], data[2], data[3]]) as usize;
                dbg!(comment_len);

                let comment = String::from_utf8_lossy(&data[4..comment_len + 4]);
                dbg!(comment);
                data = &data[comment_len + 8..];
            }

            dbg!(user_comment_list_len);
        }

        if block.header.last {
            break;
        }
    }

    println!("fin");

    Ok(())
}
