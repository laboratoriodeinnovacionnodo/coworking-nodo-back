import {
  BadRequestException,
  Injectable,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { CreateAdminDto } from './dto/create-admin.dto';
import { PrismaService } from 'prisma/prisma.service';
import { UpdateAdminDto } from './dto/update-admin.dto';

@Injectable()
export class AuthService {
  constructor(private prisma: PrismaService) {}

  // 🔐 LOGIN
  async login(email: string, password: string) {
    const admin = await this.prisma.admin.findUnique({
      where: { email },
    });

    if (!admin || admin.password !== password) {
      throw new UnauthorizedException('Credenciales inválidas');
    }

    return {
      id: admin.id,
      email: admin.email,
    };
  }

  // ➕ CREATE ADMIN
  async createAdmin(dto: CreateAdminDto) {
    const exists = await this.prisma.admin.findUnique({
      where: { email: dto.email },
    });

    if (exists) {
      throw new BadRequestException('El email ya está registrado');
    }

    return this.prisma.admin.create({
      data: dto,
      select: {
        id: true,
        email: true,
        createdAt: true,
      },
    });
  }

  // 📄 FIND ALL ADMINS
  async findAllAdmins() {
    return this.prisma.admin.findMany({
      select: {
        id: true,
        email: true,
        createdAt: true,
      },
    });
  }

  // 🔍 FIND ADMIN BY ID
  async findAdminById(id: number) {
    const admin = await this.prisma.admin.findUnique({
      where: { id },
      select: {
        id: true,
        email: true,
        createdAt: true,
      },
    });

    if (!admin) {
      throw new NotFoundException('Admin no encontrado');
    }

    return admin;
  }

  // ✏️ UPDATE ADMIN
  async updateAdmin(id: number, dto: UpdateAdminDto) {
    await this.findAdminById(id);

    return this.prisma.admin.update({
      where: { id },
      data: dto,
      select: {
        id: true,
        email: true,
        createdAt: true,
      },
    });
  }

  // 🗑 DELETE ADMIN
  async deleteAdmin(id: number) {
    await this.findAdminById(id);

    return this.prisma.admin.delete({
      where: { id },
      select: {
        id: true,
        email: true,
      },
    });
  }
}
